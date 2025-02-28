require 'spec_helper'

describe ACH::Records::BatchHeader do
  before(:each) do
    @record = ACH::Records::BatchHeader.new
  end

  it_behaves_like 'a batch summary'

  describe 'same day ach' do
    it 'should create with string company_descriptive_date' do
      @record.company_descriptive_date = 'sd1300'
      expect(@record.company_descriptive_date_to_ach).to eq('SD1300')
    end
  end

  describe '#standard_entry_class_code' do
    it 'should default to PPD' do
      expect(@record.standard_entry_class_code_to_ach).to eq('PPD')
    end

    it 'should be capitalized' do
      @record.standard_entry_class_code = 'ccd'
      expect(@record.standard_entry_class_code_to_ach).to eq('CCD')
    end

    it 'should be exactly three characters' do
      expect { @record.standard_entry_class_code = 'CCDA' }.
        to raise_error(ACH::InvalidError)
      expect { @record.standard_entry_class_code = 'CC' }.
        to raise_error(ACH::InvalidError)
      expect { @record.standard_entry_class_code = 'CCD' }.not_to raise_error
    end

    it 'should be limited to real codes'
  end

  describe '#settlement_date' do
    it 'should be a date' do
      expect { @record.settlement_date = '0' }.
        to raise_error(ACH::InvalidError)
      expect { @record.settlement_date = '0000' }.
        to raise_error(ACH::InvalidError)
      expect { @record.settlement_date = Date.today }.not_to raise_error
    end

    it 'should be stringified as a 3-digit day of year' do
      @record.settlement_date = Date.ordinal(2013, 1)
      expect(@record.settlement_date_to_ach).to eq('001')
    end

    it 'should be stringified as 3 spaces if nil' do
      @record.settlement_date = nil
      expect(@record.settlement_date_to_ach).to eq('   ')
    end
  end
end
