require 'edfize/ydf_signal'
require 'edfize/event'

module Edfize
  class Ydf
    # YDF File Path
    attr_reader   :filename

    # Header Information
    attr_accessor :version
    attr_accessor :local_patient_identification
    attr_accessor :start_date_of_recording
    attr_accessor :start_time_of_recording
    attr_accessor :reserved
    attr_accessor :number_of_bytes_in_header
    attr_accessor :study_duration
    attr_accessor :number_of_signals
    attr_accessor :eeg_channel_config
    attr_accessor :number_of_event_lists
    attr_accessor :error_code
    attr_accessor :reserved_space
    attr_accessor :signal_header
    attr_accessor :event_header

    attr_accessor :signals
    attr_accessor :events

    HEADER_CONFIG = {
      version:                        { size:  8, after_read: :strip,  name: 'Version' },
      local_patient_identification:   { size: 16, after_read: :strip, name: 'Local Patient Identification' },
      start_date_of_recording:        { size:  8,                     name: 'Start Date of Recording', description: '(dd.mm.yy)' },
      start_time_of_recording:        { size:  8,                     name: 'Start Time of Recording', description: '(hh.mm.ss)'},
      reserved:                       { size: 16,                     name: 'Reserved' },
      number_of_bytes_in_header:      { size:  8, after_read: :to_i,  name: 'Number of Bytes in Header' },
      study_duration:                 { size:  8, after_read: :to_i,  name: 'Study Duration'},
      number_of_signals:              { size:  4, after_read: :to_i,  name: 'Number of YdfSignals' },
      eeg_channel_config:             { size:  4, after_read: :strip, name: 'EEG Channel Configuration'}, 
      number_of_event_lists:          { size:  4, after_read: :to_i,  name: 'Number of Event Lists'},
      error_code:                     { size:  4, after_read: :strip,  name: 'Error Code'},
      reserved_space:                 { size: 40,                     name: 'Reserved Space'}
      #total size 128
      #signal_header:                  { size: 224, after_read: :strip, name: 'YdfSignal for each header'},
      #event_header:                   { size:  4, after_read:  :strip, name: 'Event Header'}
      
    }

    HEADER_OFFSET = HEADER_CONFIG.collect{|k,h| h[:size]}.inject(:+)


    SIZE_OF_SAMPLE_IN_BYTES = 2
    SIZE_OF_EVENTS_IN_BYTES = 65

    # Used by tests
    RESERVED_SIZE = HEADER_CONFIG[:reserved][:size]

    def self.create(filename, &block)
      edf = self.new(filename)
      yield edf if block_given?
      edf
    end

    def initialize(filename)
      @filename = filename
      @signals = []
      @events = []

      read_header
      read_signal_header
      read_event_header
      self
    end

    def load_signals
      get_data_records
    end

    def load_ydf_events
      get_event_data_records
    end

    # Epoch Number is Zero Indexed, and Epoch Size is in Seconds (Not Data Records)
    def load_epoch(epoch_number, epoch_size)
      # reset_signals!
      load_digital_signals_by_epoch(epoch_number, epoch_size)
      calculate_physical_values!
    end

    def size_of_header
      HEADER_OFFSET + ns * YdfSignal::SIGNAL_CONFIG.collect{|k,h| h[:size]}.inject(:+) + ne * Event::EVENT_CONFIG.collect{|k,h| h[:size]}.inject(:+)
    end

    def expected_size_of_header
      @number_of_bytes_in_header
    end

    # Total File Size In Bytes
    def edf_size
      File.size(@filename)
    end

    # Data Section Size In Bytes
    def expected_data_size
      (@signals.collect(&:samples_per_data_record).inject(:+).to_i * @number_of_signals * SIZE_OF_SAMPLE_IN_BYTES) + (@events.collect(&:file_length).inject(:+).to_i * @number_of_event_lists * SIZE_OF_SAMPLE_IN_BYTES)
    end

    def expected_signal_data_size
      (@signals.collect(&:samples_per_data_record).inject(:+).to_i * @number_of_signals * SIZE_OF_SAMPLE_IN_BYTES)
    end

    def expected_event_data_size
      (@events.collect(&:file_length).inject(:+).to_i * @number_of_event_lists * SIZE_OF_EVENTS_IN_BYTES)
    end

    def expected_edf_size
      expected_data_size + size_of_header
    end

    def section_value_to_string(section)
      self.instance_variable_get("@#{section}").to_s
    end

    def section_units(section)
      units = HEADER_CONFIG[section][:units].to_s
      result = if units == ''
        ''
      else
        " #{units}" + (self.instance_variable_get("@#{section}") == 1 ? '' : 's')
      end
      result
    end

    def section_description(section)
      description = HEADER_CONFIG[section][:description].to_s
      result = if description == ''
        ''
      else
        " #{description}"
      end
      result
    end

    def print_header
      puts "\nEDF                            : #{@filename}"
      puts "Total File Size                : #{edf_size} bytes"
      puts "\nHeader Information"
      HEADER_CONFIG.each do |section, hash|
        puts "#{hash[:name]}#{' '*(31 - hash[:name].size)}: " + section_value_to_string(section) + section_units(section) + section_description(section)
      end
      puts "\nYdfSignal Information"
      signals.each_with_index do |signal, index|
        puts "\n  Position                     : #{index + 1}"
        signal.print_header
      end
      puts "\nEvent Information"
      events.each_with_index do |event, index|
        puts "\n  Position                     : #{index + 1}"
        event.print_header
      end
      puts "\nGeneral Information"
      puts "Size of Header (bytes)         : #{size_of_header}"
      puts "Size of Data   (bytes)         : #{data_size}"
      puts "Total Size     (bytes)         : #{edf_size}"

      puts "Expected Size of Header (bytes): #{expected_size_of_header}"
      #puts "Expected Size of Data   (bytes): #{expected_data_size}"
      #puts "Expected Total Size     (bytes): #{expected_edf_size}"
    end

    protected

    def read_header
      HEADER_CONFIG.keys.each do |section|
        read_header_section(section)
      end
    end

    def read_header_section(section)
      result = IO.binread(@filename, HEADER_CONFIG[section][:size], compute_offset(section) )
      result = result.to_s.send(HEADER_CONFIG[section][:after_read]) unless HEADER_CONFIG[section][:after_read].to_s == ''
      self.instance_variable_set("@#{section}", result)
    end

    def compute_offset(section)
      offset = 0
      HEADER_CONFIG.each do |key, hash|
        break if key == section
        offset += hash[:size]
      end
      offset
    end

    def ns
      @number_of_signals
    end

    def ne
      @number_of_event_lists
    end

    def reset_signals!
      @signals = []
      read_signal_header
    end

    def create_signals
      (0..ns-1).to_a.each do |signal_number|
        @signals[signal_number] ||= YdfSignal.new()
      end
    end

    def create_events
      (0..ne-1).to_a.each do |event_number|
        @events[event_number] ||= Event.new()
      end
    end
    
    def read_signal_header
      create_signals
      YdfSignal::SIGNAL_CONFIG.keys.each do |section|
        read_signal_header_section(section)
      end
    end

    def read_event_header
      create_events
      Event::EVENT_CONFIG.keys.each do |section|
        read_event_header_section(section)
      end
    end

    def compute_signal_offset(section)
      offset = 0
      YdfSignal::SIGNAL_CONFIG.each do |key, hash|
        #puts "KEY:SECTION #{key} - #{key.class} : #{section} - #{section.class} : #{hash} - #{hash[:size]}"
        break if key == section
        offset += hash[:size]
      end
      #puts "offset: #{offset}"
      offset
    end

    def compute_event_offset(section)
      offset = 0
      Event::EVENT_CONFIG.each do |key, hash|
        break if key == section
        offset += hash[:size]
      end
      offset
    end

    def read_signal_header_section(section)
      offset = HEADER_OFFSET 
      signal_offset = compute_signal_offset(section)
      (0..ns-1).to_a.each do |signal_number|
        section_size = YdfSignal::SIGNAL_CONFIG[section][:size]
        signal_header_size = YdfSignal::SIGNAL_CONFIG.collect{|k,h| h[:size]}.inject(:+)
        #puts "section: #{section} : #{section_size} : #{offset} +: #{signal_number} *: #{signal_header_size} +: #{signal_offset}"
        #
        result = IO.binread(@filename, section_size, offset+(signal_number*signal_header_size)+signal_offset)
        result = result.to_s.send(YdfSignal::SIGNAL_CONFIG[section][:after_read]) unless YdfSignal::SIGNAL_CONFIG[section][:after_read].to_s == ''
        @signals[signal_number].send("#{section}=", result)
      end
    end

    def read_event_header_section(section)
      offset = HEADER_OFFSET + YdfSignal::SIGNAL_CONFIG.collect{|k,h| h[:size]}.inject(:+) * ns
      event_offset = compute_event_offset(section)
      (0..ne-1).to_a.each do |event_number|
        section_size = Event::EVENT_CONFIG[section][:size]
        event_header_size = Event::EVENT_CONFIG.collect{|k,h| h[:size]}.inject(:+)
        #puts "section: #{section} : #{section_size} : #{offset} +: #{event_number} *: #{event_header_size} +: #{event_offset}"
        #
        result = IO.binread(@filename, section_size, offset+(event_number*event_header_size)+event_offset)
        result = result.to_s.send(Event::EVENT_CONFIG[section][:after_read]) unless Event::EVENT_CONFIG[section][:after_read].to_s == ''
        @events[event_number].send("#{section}=", result)
      end
    end

    # def read_event_header_section(section)
    #   ### add offset for event section BROKEN
    #   offset = HEADER_OFFSET + ne * compute_event_offset(section)
    #   (0..ne-1).to_a.each do |event_number|
    #     section_size = Event::EVENT_CONFIG[section][:size]
    #     result = IO.binread(@filename, section_size, offset+(event_number*section_size))
    #     result = result.to_s.send(Event::EVENT_CONFIG[section][:after_read]) unless Event::EVENT_CONFIG[section][:after_read].to_s == ''
    #     @events[event_number].send("#{section}=", result)
    #   end
    # end

    def get_data_records
      load_digital_signals()
      calculate_physical_values!()
    end

    def get_event_data_records
      load_events()
    end

    def load_digital_signals_by_epoch(epoch_number, epoch_size)
      size_of_data_record_in_bytes = @signals.collect(&:samples_per_data_record).inject(:+).to_i * SIZE_OF_SAMPLE_IN_BYTES
      data_records_to_retrieve = (epoch_size / @duration_of_a_data_record rescue 0)
      length_of_bytes_to_read = (data_records_to_retrieve+1) * size_of_data_record_in_bytes
      epoch_offset_size = epoch_number * epoch_size * size_of_data_record_in_bytes # TODO: The size in bytes of an epoch

      all_signal_data = (IO.binread(@filename, length_of_bytes_to_read, size_of_header + epoch_offset_size).unpack('s<*') rescue [])
      load_signal_data(all_signal_data, data_records_to_retrieve+1)
    end

    # 16-bit signed integer size = 2 Bytes = 2 ASCII characters
    # 16-bit signed integer in "Little Endian" format (least significant byte first)
    # unpack:  s<         16-bit signed, (little-endian) byte order
    # limit to the signal data
    def load_digital_signals
      all_signal_data = IO.binread(@filename, expected_signal_data_size, size_of_header).unpack('s<*')
      load_signal_data(all_signal_data, @number_of_signals)
    end

    def load_events
      #find the end of signal data and offset to there
      #first file data : size -> 1643911 offset -> 37888084
      #find the full size of the file
      total_file_length = IO.binread(@filename).length
      #find the start of all the events
      all_samples_per_data_record = @events.collect{|s| s.file_length}
      total_samples_per_data_record = all_samples_per_data_record.inject(:+).to_i

      all_event_data = IO.binread(@filename, total_samples_per_data_record, total_file_length - total_samples_per_data_record)
      load_event_data(all_event_data, @number_of_event_lists)
    end

    def load_signal_data(all_signal_data, data_records_retrieved)
      all_samples_per_data_record = @signals.collect{|s| s.samples_per_data_record}
      total_samples_per_data_record = all_samples_per_data_record.inject(:+).to_i

      offset = 0
      offsets = []
      all_samples_per_data_record.each do |samples_per_data_record|
        offsets << offset
        offset += samples_per_data_record
      end

      (0..data_records_retrieved-1).to_a.each do |data_record_index|
        @signals.each_with_index do |signal, signal_index|
          read_start = data_record_index * total_samples_per_data_record + offsets[signal_index]
          (0..signal.samples_per_data_record - 1).to_a.each do |value_index|
            signal.digital_values << all_signal_data[read_start+value_index]
          end
        end
      end
    end

    def load_event_data(all_event_data, data_records_retrieved)
      all_samples_per_data_record = @events.collect{|s| s.file_length}
      total_samples_per_data_record = all_samples_per_data_record.inject(:+).to_i

      offset = 0
      offsets = []
      all_samples_per_data_record.each do |samples_per_data_record|
        offsets << offset
        offset += samples_per_data_record
      end
      @events.each do |event|
        #puts "event this : #{event.start_offset} : #{event.file_length} : #{event.start_offset + event.file_length}"
        #parse the json values out of the file instead of capturing the entire file.
        #event.event_values << JSON.parse(all_event_data[event.start_offset..(event.start_offset + event.file_length - 1)], allow_nan: true)
        event.event_json = JSON.parse(all_event_data[event.start_offset..(event.start_offset + event.file_length - 1)], allow_nan: true)
      end
      # (0..data_records_retrieved-1).to_a.each do |data_record_index|
      #   @events.each_with_index do |event, event_index|
      #     #read_start = data_record_index * total_samples_per_data_record + offsets[event_index]
      #     puts "events: #{event.start_offset} : #{event.file_length}"
      #     event.event_values << all_event_data[event.start_offset..event.file_length]
      #     # (0..event.file_length - 1).to_a.each do |value_index|
      #     #   puts "read st: #{read_start} : #{value_index} : #{all_event_data.length}"
      #     #   event.event_values << all_event_data[read_start+value_index]
      #     # end
      #   end
      # end
    end

    def calculate_physical_values!
      @signals.each{|signal| signal.calculate_physical_values!}
    end

    def data_size
      IO.binread(@filename, nil, size_of_header).size
    end
  end
end
