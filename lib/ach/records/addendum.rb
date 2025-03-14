module ACH::Records
  class Addendum < Record
    @fields = []

    const_field :record_type, '7'
    field :type_code, String, nil, '05', /\A\d{2}\z/
    field :payment_data, String, lambda { |f| left_justify(f, 80)}
    field :sequence_number, Integer, lambda { |f| sprintf('%04d', f)}
    field :entry_detail_sequence_number, Integer, lambda { |f| sprintf('%07d', f)}

    # NOTE: When the API can change, these subclasses should override the
    #       redundant fields in Addendum
    class NotificationOfChange < Addendum
      @fields = Addendum.fields

      def reason_code
        payment_data[0..2]
      end

      def original_entry_trace_number
        payment_data[3..17]
      end

      def original_receiving_dfi_identification
        payment_data[24..31]
      end

      def corrected_data
        payment_data[32..60].strip
      end
    end

    class Return < Addendum
      @fields = Addendum.fields

      def contested_return?
        reason_code.in?(%w[R71 R72 R73 R74 R75 R76 R77])
      end

      def reason_code
        payment_data[0..2]
      end

      def original_entry_trace_number
        payment_data[3..17]
      end

      def date_of_death
        Date.parse(payment_data[18..23]) rescue nil
      end
      alias_method :date_original_entry_returned, :date_of_death

      def original_receiving_dfi_identification
        payment_data[24..31]
      end

      def addenda_information
        payment_data[32..75].strip
      end

      def original_settlement_date
        payment_data[32..34].to_i if contested_return?
      end

      def return_trace_number
        payment_data[35..49] if contested_return?
      end

      def return_settlement_date
        payment_data[50..52].to_i if contested_return?
      end

      def return_reason_code
        payment_data[53..54] if contested_return?
      end

      def dishonored_return_trace_number
        payment_data[55..69] if contested_return?
      end

      def dishonored_return_settlement_date
        payment_data[70..72].to_i if contested_return?
      end

      def dishonored_return_reason_code
        payment_data[73..74] if contested_return?
      end
    end
  end
end
