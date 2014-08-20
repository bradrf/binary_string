# A mixin to extend a binary string with various helpful utilities to walk and show its content
# nicely.
#
module BinaryString

  CONSUME_TYPE_TO_LEN = {
    'C' => 1,
    'N' => 4,
    'n' => 2,
    'Z' => 1,
    'V' => 4,
    'v' => 2,
    'Q' => 8,
    '!' => 4, # my own marker for network order bignums
  }

  # Ruby's pack doesn't support Bignums in network byte order, so this is how we will work around
  # it.
  LITTLE_ENDIAN = ([42].pack('i')[0] == 42)

  def self.mix_it_in!
    String.include(self)
  end

  def self.mix_in(string_or_io)
    if string_or_io.is_a? IO
      def string_or_io.read_with_consumer_at(offset, length)
        self.seek(offset)
        self.read(length).extend(BinaryString)
      end
    else
      string_or_io.extend(self)
    end
    string_or_io
  end

  ######################################################################
  # Methods mixed in to strings:

  def consume_pos
    @consume_pos ||= 0
  end

  # Grab the indicated type off the front of the string via unpack-like formatters. This constraint
  # is in place in order to deterministically know the number of bytes needed for each operation.
  #
  def consume(type, count = 1)
    raise TypeError unless len = CONSUME_TYPE_TO_LEN[type]

    fmt = "@#{consume_pos}"

    if '!' == type
      if LITTLE_ENDIAN
        bignum = true
        type   = 'N'
        count *= 2
      else
        type = 'Q'
      end
    end

    if count > 1
      len *= count
      fmt << type + count.to_s
    else
      fmt << type
    end

    raise EOFError if length < consume_pos + len

    ret = unpack(fmt)
    @consume_pos += len

    if bignum
      newret = []
      num    = nil
      ret.each do |n|
        if num
          newret << (num | n)
          num = nil
        else
          num = n << 32
        end
      end
      ret = newret
    end

    ret.size > 1 ? ret : ret.first
  end

  # Grab a chunk off the front with the helper extended into it for further analysis.
  #
  def consume_chunk(len)
    raise EOFError if length < len

    chunk = slice(consume_pos, len)
    @consume_pos += len

    chunk.extend(BinaryString)
  end

  # Seek the position to a specific spot in the string. The previous value will be returned (a seek
  # of 0 is equivalent to a "rewind"). If a negative value is provided, the seek will be relative.
  #
  def consume_seek(pos)
    orig = consume_pos
    if pos < 0
      pos = consume_pos + pos
      pos = 0 if pos < 0
    end
    @consume_pos = pos
    orig
  end

  # Obtain the length of the remaining string not yet consumed.
  #
  def consume_length
    length - consume_pos
  end

  # Reduce the string's length relative to the current consume position.
  #
  def consume_chop!(newlen)
    slice!(consume_pos+newlen..-1)
  end

  # Append the objects to the string packed as 'type' unless an optional hash key ':at' is provided
  # as the final argument with an offset where in the string the store should occur.
  #
  def store(type, *objs)
    opts = objs.delete_at(-1) if Hash === objs.last
    if '!' == type
      if LITTLE_ENDIAN
        str = ''
        objs.each do |obj|
          str << [obj].pack('Q').reverse!
        end
      else
        str = objs.pack('Q' + objs.size.to_s)
      end
    else
      str = objs.pack(type + objs.size.to_s)
    end
    if opts && pos = opts[:at]
      self.slice!(pos, str.length)
      self.insert(pos, str)
    else
      self.<< str
    end
    self
  end

  # Dump out the string (optionally limited to max bytes) to the I/O object. Show four columns each
  # of hexadecimal values, decimal values, collected 16 bit values (unsigned shorts), collected 32
  # bit values (unsigned longs), and finally any printable ASCII chars.
  #
  def hexdump(max = length, io = $stdout, reported_idx_offset = 0)
    idx = consume_pos
    len = length - idx
    if len < max
      max = idx + len
    else
      max += idx
    end

    showlen = max - idx
    io.puts("%s bytes (at #{idx+reported_idx_offset}):" %
            (showlen == len ? showlen.to_s : "#{showlen}/#{len}"))

    while idx < max
      offset = '%010d: ' % (idx+reported_idx_offset)
      hex = ''
      dec = ''
      chr = ''

      u16_1 = 0
      u16_2 = 0

      rem = max - idx

      (rem > 3 ? 4 : rem).times do |i|
        byte = getbyte(idx)

        hex << '%02x ' % byte
        dec <<  '%3u ' % byte

        if 0x1f < byte && byte < 0x7f
          chr <<  byte.chr
        else
          chr << ?.
        end

        if i < 2
          u16_1 = (u16_1 << 8) | byte
        else
          u16_2 = (u16_2 << 8) | byte
        end

        idx += 1
      end

      (rem < 4 ? 4 - rem : 0).times do
        hex << '   '
        dec << '    '
      end

      if rem < 4
        short = '%6u %6s ' % [u16_1, ' ']
        long  = '%10u ' % u16_1
      else
        short = '%6u %6u ' % [u16_1, u16_2]
        long  = '%10u ' % ((u16_1 << 16) | u16_2)
      end

      io.puts offset + hex + '| ' + dec + '| ' + short + '| ' + long + '| ' + chr
    end
  end

end # BinaryString module
