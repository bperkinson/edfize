module Edfize
  class Event
    attr_accessor :label, :read_only, :start_offset, :file_length

    EVENT_CONFIG = {
      label:                   { size: 32, after_read: :strip, name: 'Label' },
      read_only:               { size:  1, after_read: :to_i,  name: 'Read Only'},
      start_offset:            { size: 16, after_read: :to_i,  name: 'Start Offset'},
      file_length:             { size: 16, after_read: :to_i,  name:  'File Length'}

    }

    def initialize
      @event_values = []
      #@digital_values = []
      #@physical_values = []
      self
    end

    def self.create(&block)
      event = self.new
      yield event if block_given?
      event
    end

    def print_header
      EVENT_CONFIG.each do |section, hash|
        puts "  #{hash[:name]}#{' '*(29 - hash[:name].size)}: " + self.send(section).to_s
      end
    end

    # Physical value (dimension PhysiDim) = (ASCIIvalue-DigiMin)*(PhysiMax-PhysiMin)/(DigiMax-DigiMin) + PhysiMin.
    # def calculate_physical_values!
    #   @physical_values = @digital_values.collect{|sample| (( sample - @digital_minimum ) * ( @physical_maximum - @physical_minimum ) / ( @digital_maximum - @digital_minimum) + @physical_minimum rescue nil) }
    # end

    # def samples
    #   @physical_values
    # end

  end
end
