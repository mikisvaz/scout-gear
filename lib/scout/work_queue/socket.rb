require 'scout/open'
require 'scout/semaphore'
require 'scout/exceptions'
class WorkQueue
  class Socket
    attr_accessor :sread, :swrite, :write_sem, :read_sem, :cleaned, :exception
    def initialize(serializer = nil)
      @sread, @swrite = Open.pipe

      @serializer = serializer || Marshal

      @key = "/" << rand(1000000000).to_s << '.' << Process.pid.to_s;
      @write_sem = @key + '.in'
      @read_sem = @key + '.out'
      Log.debug "Creating socket semaphores: #{@key}"
      ScoutSemaphore.create_semaphore(@write_sem,1)
      ScoutSemaphore.create_semaphore(@read_sem,1)
    end

    def socket_id
      @key
    end

    def clean
      @cleaned = true
      @sread.close unless @sread.closed?
      @swrite.close unless @swrite.closed?
      Log.low "Destroying socket semaphores: #{[@key] * ", "}"
      ScoutSemaphore.delete_semaphore(@write_sem)
      ScoutSemaphore.delete_semaphore(@read_sem)
    end


    def dump(obj)
      stream = @swrite
      obj.concurrent_stream = nil if obj.respond_to?(:concurrent_stream)
      case obj
      when Integer
        size_head = [obj,"I"].pack 'La'
        str = size_head
      when nil
        size_head = [0,"N"].pack 'La'
        str = size_head
      when String
        payload = obj
        size_head = [payload.bytesize,"C"].pack 'La'
        str = size_head << payload
      else
        payload = @serializer.dump(obj)
        size_head = [payload.bytesize,"S"].pack 'La'
        str = size_head << payload
      end

      write_length = str.length
      wrote = stream.write(str) 
      while wrote < write_length
        wrote += stream.write(str[wrote..-1]) 
      end
    end

    def load
      stream = @sread
      size_head = Open.read_stream stream, 5

      size, type = size_head.unpack('La')

      return nil if type == "N"
      return size.to_i if type == "I"
      begin
        payload = Open.read_stream stream, size
        case type
        when "S"
          begin
            @serializer.load(payload)
          rescue Exception
            Log.exception $!
            raise $!
          end
        when "C"
          payload
        end
      rescue TryAgain
        retry
      end
    end

    def closed_read?
      @sread.closed?
    end

    def closed_write?
      @swrite.closed?
    end

    def close_write
      self.dump ClosedStream.new
      @swrite.close unless closed_write?
    end

    def close_read
      @sread.close unless closed_read?
    end

    #{{{ ACCESSOR
    def push(obj)
      ScoutSemaphore.synchronize(@write_sem) do
        self.dump(obj)
      end
    end

    def pop
      ScoutSemaphore.synchronize(@read_sem) do
        res = self.load
        raise res if ClosedStream === res
        res
      end
    end

    def abort(exception)
      @exception = exception
      @swrite.close unless closed_write?
    end

    alias write push

    alias read pop
  end
end
