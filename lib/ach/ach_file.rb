require 'date'

module ACH
  class ACHFile
    include FieldIdentifiers

    attr_reader :batches
    attr_reader :header
    attr_reader :control

    def initialize data=nil
      @batches = []
      @header = Records::FileHeader.new
      @control = Records::FileControl.new

      if data
        if (data.encode(Encoding.find('ASCII'), **ENCODING_OPTIONS) =~ /\n|\r\n/).nil?
          parse_fixed(data)
        else
          parse(data)
        end
      end
    end

    # @param eol [String] Line ending, default to CRLF
    def to_s eol = "\r\n"
      records = []
      records << @header

      @batches.each_with_index do |batch, index|
        batch.header.batch_number ||= index + 1
        records += batch.to_ach
      end
      records << @control

      ### PNM-433 ###
      ### Making nine lines optional breaks file control, in the interest of minimal gem file modification
      ### use the wrapper to add/remove nine lines in nacha support concern and leave this as it is

      nines_needed = 10 - (records.length % 10)
      nines_needed = nines_needed % 10
      nines_needed.times { records << Records::Nines.new() }

      @control.batch_count = @batches.length
      @control.block_count = (records.length / 10).ceil

      @control.entry_count = 0
      @control.debit_total = 0
      @control.credit_total = 0
      @control.entry_hash = 0

      @batches.each do | batch |
        @control.entry_count += batch.entries.inject(0) { |total, entry| total + entry.records_count }
        @control.debit_total += batch.control.debit_total
        @control.credit_total += batch.control.credit_total
        @control.entry_hash += batch.control.entry_hash
      end

      ### PNM-433 ###
      # tried to change eol to just \n, but this breaks addenda lines where "\r\n is default
      # in short just replace "\r\n of the whole nacha string with "\n" to keep this simple
      # was ==>  records.collect { |r| r.to_ach }.join(eol) + eol

      (records.collect { |r| r.to_ach }.join(eol) + eol).gsub("\r\n", "\n")
    end

    def report
      to_s # To ensure correct records
      lines = []

      @batches.each do | batch |
        batch.entries.each do | entry |
          lines << left_justify(entry.individual_name + ": ", 25) +
              sprintf("% 7d.%02d", entry.amount / 100, entry.amount % 100)
        end
      end
      lines << ""
      lines << left_justify("Debit Total: ", 25) +
          sprintf("% 7d.%02d", @control.debit_total / 100, @control.debit_total % 100)
      lines << left_justify("Credit Total: ", 25) +
          sprintf("% 7d.%02d", @control.credit_total / 100, @control.credit_total % 100)

      lines.join("\r\n")
    end

    def parse_fixed data
      # replace with a space to preserve the record-lengths
      encoded_data = data.encode(Encoding.find('ASCII'), invalid: :replace, undef: :replace, replace: ' ')
      parse encoded_data.scan(/.{94}/).join("\n")
    end

    def parse data
      fh =  self.header
      batch = nil
      bh = nil
      ed = nil

      data.strip.split(/\n|\r\n/).each do |line|
        type = line[0].chr
        case type
        when '1'
          fh.immediate_destination          = line[03..12].strip
          fh.immediate_origin               = line[13..22].strip
          fh.transmission_datetime          = Time.utc('20'+line[23..24], line[25..26], line[27..28], line[29..30], line[31..32])
          fh.file_id_modifier               = line[33..33]
          fh.immediate_destination_name     = line[40..62].strip
          fh.immediate_origin_name          = line[63..85].strip
          fh.reference_code                 = line[86..93].strip
        when '5'
          self.batches << batch unless batch.nil?
          batch = ACH::Batch.new
          bh = batch.header
          bh.company_name                   = line[4..19].strip
          ### PNM-433 ###
          # add ability to parse company discretionary data which is used to in bapi ach confirmation
          # heavily used in wells fargo nacha ach confirmation, which in turn marks the batch as settled
          # was ==> not defined in the ach gem file
          bh.company_discretionary_data     = line[20..39].strip
          bh.company_identification         = line[40..49].gsub(/\A1/, '')

          # Does not try to guess if company identification is an EIN
          # TODO fix differently when I feel like breaking backwards
          # compatibility.
          bh.full_company_identification    = line[40..49]
          bh.standard_entry_class_code      = line[50..52].strip
          bh.company_entry_description      = line[53..62].strip
          bh.company_descriptive_date       = Date.parse(line[63..68]) rescue nil # this can be various formats
          bh.effective_entry_date           = Date.parse(line[69..74])
          settlement_date_day_of_year       = line[75..77].to_i
          if settlement_date_day_of_year.positive?
            settlement_date_year = settlement_date_day_of_year < fh.transmission_datetime.yday ? fh.transmission_datetime.year + 1 : fh.transmission_datetime.year
            bh.settlement_date   = Date.ordinal(settlement_date_year, settlement_date_day_of_year) rescue nil
          end
          bh.originating_dfi_identification = line[79..86].strip
        when '6'
          ed = ACH::CtxEntryDetail.new
          ed.transaction_code               = line[1..2]
          ed.routing_number                 = line[3..11]
          ed.account_number                 = line[12..28].strip
          ed.amount                         = line[29..38].to_i # cents
          ed.individual_id_number           = line[39..53].strip
          ed.individual_name                = line[54..75].strip
          ed.originating_dfi_identification = line[79..86]
          ed.trace_number                   = line[87..93].to_i
          batch.entries << ed
        when '7'
          type_code = line[1..2]
          ad = case type_code
          when '98'
            ACH::Addendum::NotificationOfChange.new
          when '99'
            ACH::Addendum::Return.new
          else
            ACH::Addendum.new
          end
          ad.type_code                      = type_code
          ad.payment_data                   = line[3..82].strip
          ad.sequence_number                = line[83..86].strip.to_i
          ad.entry_detail_sequence_number   = line[87..93].to_i
          ed.addenda << ad
        when '8'
          # skip
        when '9'
          ### PNM-433 ###
          # Need this to parse nacha response code from the response file
          # the filler is a custom field in the file control where we look for response code
          # was ==> skip and not defined in the ach gem file

          @control = Records::FileControl.new
          @control.filler = line[55..93]
        else
          raise UnrecognizedTypeCode, "Didn't recognize type code #{type} for this line:\n#{line}"
        end
      end

      self.batches << batch unless batch.nil?
      to_s
    end
  end
end
