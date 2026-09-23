# frozen_string_literal: true

module RedmineAiHelper
  module Util
    # Reads a log file for the log functions of SystemTools without loading the
    # whole file: the tail and the search read backwards from the end in chunks,
    # up to the size the file had when it was opened.
    #
    # The reader depends on nothing but the given path (no User.current,
    # AiHelperSetting or Rails.logger), so it can be tested with temporary files.
    # Error messages and results identify the file by its base name only.
    class LogFileReader
      # Number of lines the tail returns when the caller does not specify one.
      DEFAULT_TAIL_LINES = 100
      # Largest number of lines the tail returns.
      MAX_TAIL_LINES = 1_000
      # Number of matches the search returns when the caller does not specify one.
      DEFAULT_MAX_MATCHES = 50
      # Largest number of matches the search returns.
      MAX_MATCHES_LIMIT = 200
      # Largest number of context lines before and after each match.
      MAX_CONTEXT_LINES = 10
      # Lines longer than this number of characters are truncated.
      MAX_LINE_CHARS = 2_000
      # The search reads at most this many bytes from the end of the file (500MB).
      MAX_SCAN_BYTES = 524_288_000
      # Size of each backward read of the tail.
      TAIL_CHUNK_BYTES = 65_536
      # Size of each backward read of the search.
      SEARCH_CHUNK_BYTES = 1_048_576
      # The tail reads at most this many bytes from the end of the file (16MB),
      # so that a log with very long lines, or no newline at all, is not read
      # in full. MAX_TAIL_LINES lines of MAX_LINE_CHARS 4-byte characters fit.
      MAX_TAIL_BYTES = 16_777_216
      # The search keeps at most this many bytes of a single line (16MB). The
      # rest of a longer line is neither matched nor returned.
      MAX_SEARCH_LINE_BYTES = 16_777_216

      # Character that replaces invalid UTF-8 bytes.
      REPLACEMENT_CHAR = "�"

      # Raised when the log file does not exist or cannot be read.
      # The message contains the file name only, never the directory.
      class FileNotReadableError < StandardError
        # @return [String] Base name of the file
        attr_reader :file_name
        # @return [Symbol] :not_found or :not_readable
        attr_reader :reason

        # @param file_name [String] Base name of the file
        # @param reason [Symbol] :not_found or :not_readable
        def initialize(file_name, reason)
          @file_name = file_name
          @reason = reason
          detail = reason == :not_found ? "does not exist" : "cannot be read"
          super("The log file #{file_name} #{detail}.")
        end
      end

      # @param path [String] File to read (the return value of LogFileLocator.resolve)
      # @param max_scan_bytes [Integer] Upper limit of bytes the search reads
      # @param max_tail_bytes [Integer] Upper limit of bytes the tail reads
      # @param max_search_line_bytes [Integer] Upper limit of bytes the search keeps of one line
      # @param tail_chunk_bytes [Integer] Size of each backward read of the tail
      # @param search_chunk_bytes [Integer] Size of each backward read of the search
      # @raise [ArgumentError] If a limit or a chunk size is not a positive integer
      def initialize(path, max_scan_bytes: MAX_SCAN_BYTES, max_tail_bytes: MAX_TAIL_BYTES,
                     max_search_line_bytes: MAX_SEARCH_LINE_BYTES,
                     tail_chunk_bytes: TAIL_CHUNK_BYTES, search_chunk_bytes: SEARCH_CHUNK_BYTES)
        sizes = { max_scan_bytes: max_scan_bytes, max_tail_bytes: max_tail_bytes,
                  max_search_line_bytes: max_search_line_bytes,
                  tail_chunk_bytes: tail_chunk_bytes, search_chunk_bytes: search_chunk_bytes }
        sizes.each do |name, value|
          raise ArgumentError, "#{name} must be a positive integer" unless value.is_a?(Integer) && value.positive?
        end

        @path = path.to_s
        @file_name = File.basename(@path)
        @max_scan_bytes = max_scan_bytes
        @max_tail_bytes = max_tail_bytes
        @max_search_line_bytes = max_search_line_bytes
        @tail_chunk_bytes = tail_chunk_bytes
        @search_chunk_bytes = search_chunk_bytes
      end

      # Returns the size and the last modification time of the file. The file is
      # opened to confirm that it can actually be read.
      # @return [Hash] { file_name:, size_bytes:, updated_at: } with updated_at in
      #   ISO 8601 in the server time zone
      # @raise [FileNotReadableError] If the file does not exist or cannot be read
      def info
        open_file do |file|
          stat = file.stat
          { file_name: @file_name, size_bytes: stat.size, updated_at: stat.mtime.iso8601 }
        end
      end

      # Reads the last lines of the file. The amount read is proportional to the
      # number of lines requested, not to the file size, and never exceeds
      # max_tail_bytes. When that limit cuts the oldest line, the line is dropped,
      # unless fewer lines than requested were found: then its end is returned
      # with truncated set, and byte_limit_reached tells the caller.
      # @param lines [Integer] Number of lines, 1..MAX_TAIL_LINES
      # @return [Hash] { file_name:, file_size_bytes:, line_numbering:, lines:,
      #   empty:, byte_limit_reached: }
      # @raise [ArgumentError] If lines is out of range
      # @raise [FileNotReadableError] If the file does not exist or cannot be read
      def tail(lines:)
        validate_range(:lines, lines, 1..MAX_TAIL_LINES)
        open_file do |file|
          size = file.size
          end_pos = content_end(file, size)
          lower_bound = end_pos - [ end_pos, @max_tail_bytes ].min
          pos = end_pos
          chunks = []
          newlines = 0
          while pos > lower_bound && newlines < lines
            length = [ @tail_chunk_bytes, pos - lower_bound ].min
            pos -= length
            chunk = file.pread(length, pos)
            newlines += chunk.count("\n")
            chunks.unshift(chunk)
          end

          reached_start = pos.zero?
          byte_limit_reached = !reached_start && pos == lower_bound && newlines < lines
          raw_lines = end_pos.zero? ? [] : to_utf8(chunks.join).split("\n", -1)
          first_line_complete = reached_start || file.pread(1, pos - 1) == "\n"
          partial = first_line_complete ? nil : raw_lines.shift
          result_lines = tail_lines(raw_lines, lines, reached_start)
          if byte_limit_reached && partial
            result_lines.unshift(self.class.build_partial_line(partial, result_lines.size + 1))
          end

          {
            file_name: @file_name,
            file_size_bytes: size,
            line_numbering: reached_start ? "from_start" : "from_end_only",
            lines: result_lines,
            empty: size.zero?,
            byte_limit_reached: byte_limit_reached
          }
        end
      end

      # Searches the file for lines that contain the keyword, reading backwards
      # from the end. After more than max_matches lines have matched, the scan
      # reads only as far as needed to fill the context lines before the kept
      # matches, and it never reads more than max_scan_bytes, so its cost does
      # not grow with the file size. When more than max_matches lines match, the
      # newest max_matches are kept and truncated is set.
      # @param keyword [String] Non-empty text, matched literally
      # @param case_sensitive [Boolean] Whether letter case must match
      # @param context_lines [Integer] Lines before and after each match, 0..MAX_CONTEXT_LINES
      # @param max_matches [Integer] Matches to return, 1..MAX_MATCHES_LIMIT
      # @return [Hash] { file_name:, file_size_bytes:, keyword:, case_sensitive:,
      #   context_lines:, max_matches:, match_count:, truncated:, scanned_bytes:,
      #   scanned_whole_file:, line_numbering:, matches: } with matches oldest
      #   first, each { before:, line:, after: }
      # @raise [ArgumentError] If an argument is empty or out of range
      # @raise [FileNotReadableError] If the file does not exist or cannot be read
      def search(keyword:, case_sensitive:, context_lines:, max_matches:)
        raise ArgumentError, "keyword must be a non-empty string" unless keyword.is_a?(String) && !keyword.empty?

        validate_range(:context_lines, context_lines, 0..MAX_CONTEXT_LINES)
        validate_range(:max_matches, max_matches, 1..MAX_MATCHES_LIMIT)
        pattern = Regexp.new(Regexp.escape(keyword), case_sensitive ? nil : Regexp::IGNORECASE)
        open_file do |file|
          size = file.size
          scan = SearchScan.new(pattern, context_lines, max_matches)
          scanned_bytes, reached_start = scan_backwards(file, size) { |text| scan.process(text) }
          scanned_whole_file = reached_start && !scan.truncated
          scan.assign_line_numbers if scanned_whole_file

          {
            file_name: @file_name,
            file_size_bytes: size,
            keyword: keyword,
            case_sensitive: case_sensitive,
            context_lines: context_lines,
            max_matches: max_matches,
            match_count: scan.matches.size,
            truncated: scan.truncated,
            scanned_bytes: scanned_bytes,
            scanned_whole_file: scanned_whole_file,
            line_numbering: scanned_whole_file ? "from_start" : "from_end_only",
            matches: scan.matches.reverse
          }
        end
      end

      # Walks the lines of a search from the newest to the oldest, collecting
      # matches with their context lines. Line objects are built only for lines
      # that are returned, and a block without a match is not split into lines
      # beyond the few kept as context for the next match.
      class SearchScan
        # @return [Array<Hash>] Matches found so far, newest first
        attr_reader :matches
        # @return [Boolean] Whether more than max_matches lines matched
        attr_reader :truncated

        # @param pattern [Regexp] Literal keyword pattern
        # @param context_lines [Integer] Lines before and after each match
        # @param max_matches [Integer] Matches to keep
        def initialize(pattern, context_lines, max_matches)
          @pattern = pattern
          @context_lines = context_lines
          @max_matches = max_matches
          @matches = []
          @waiting = [] # matches that still need lines before them
          @recent = []  # [raw, lines_from_end] of the newest lines seen, newest first
          @lines_from_end = 0
          @truncated = false
        end

        # Processes a block of complete lines.
        # @param text [String] Valid UTF-8 lines joined by "\n", in file order
        # @return [Boolean] true when the scan can stop
        def process(text)
          # A block holding a single empty line, which String#split would drop.
          return process_line(text) if text.empty?

          if @waiting.empty? && !@pattern.match?(text)
            skip_block(text)
            return false
          end

          text.split("\n", -1).reverse_each do |raw|
            return true if process_line(raw)
          end
          false
        end

        # Sets line_number on every returned line once the whole file was read.
        def assign_line_numbers
          @matches.each do |match|
            (match[:before] + [ match[:line] ] + match[:after]).each do |line|
              line[:line_number] = @lines_from_end - line[:lines_from_end] + 1
            end
          end
        end

        private

        # Counts the lines of a block without a match, keeping only its oldest
        # lines as the lines after the next (older) match.
        # @param text [String] Lines joined by "\n", in file order
        def skip_block(text)
          count = text.count("\n") + 1
          if @context_lines.positive?
            head = text.split("\n", @context_lines + 1).first([ @context_lines, count ].min)
            (head.size - 1).downto(0) { |index| remember(head[index], @lines_from_end + count - index) }
          end
          @lines_from_end += count
        end

        # @param raw [String] One line, newer lines having been processed already
        # @return [Boolean] true when the scan can stop
        def process_line(raw)
          @lines_from_end += 1
          unless @waiting.empty?
            line = LogFileReader.build_line(raw, @lines_from_end)
            @waiting.each { |match| match[:before].unshift(line) }
            @waiting.reject! { |match| match[:before].size >= @context_lines }
          end
          record_match(raw) if !@truncated && @pattern.match?(raw)
          remember(raw, @lines_from_end) if @context_lines.positive?
          @truncated && @waiting.empty?
        end

        # @param raw [String] The matching line
        def record_match(raw)
          if @matches.size == @max_matches
            @truncated = true
            return
          end
          after = @recent.reverse.map { |recent_raw, from_end| LogFileReader.build_line(recent_raw, from_end) }
          match = { before: [], line: LogFileReader.build_line(raw, @lines_from_end), after: after }
          @matches << match
          @waiting << match if @context_lines.positive?
        end

        # Keeps a line as one of the newest context_lines lines seen.
        # @param raw [String]
        # @param lines_from_end [Integer]
        def remember(raw, lines_from_end)
          @recent.push([ raw, lines_from_end ])
          @recent.shift if @recent.size > @context_lines
        end
      end
      private_constant :SearchScan

      # Builds the line object returned to the caller.
      # @param raw [String] UTF-8 line without the newline
      # @param lines_from_end [Integer] Position counted from the last line (1)
      # @param line_number [Integer, nil] Position counted from the first line (1)
      # @return [Hash] { line_number:, lines_from_end:, content:, truncated: }
      def self.build_line(raw, lines_from_end, line_number = nil)
        content = raw.delete_suffix("\r")
        truncated = content.length > MAX_LINE_CHARS
        if truncated
          content = "#{content[0, MAX_LINE_CHARS]} …[truncated #{content.length - MAX_LINE_CHARS} chars]"
        end
        { line_number: line_number, lines_from_end: lines_from_end, content: content, truncated: truncated }
      end

      # Builds the line object for the end of a line whose start lies beyond
      # the byte limit of the tail. The last MAX_LINE_CHARS characters are kept.
      # @param raw [String] UTF-8 end of the line, without the newline
      # @param lines_from_end [Integer] Position counted from the last line (1)
      # @return [Hash] { line_number: nil, lines_from_end:, content:, truncated: true }
      def self.build_partial_line(raw, lines_from_end)
        content = raw.delete_suffix("\r")
        content = content[-MAX_LINE_CHARS..] if content.length > MAX_LINE_CHARS
        { line_number: nil, lines_from_end: lines_from_end, content: "[start of line not read]… #{content}", truncated: true }
      end

      private

      # Reads the file backwards in chunks of search_chunk_bytes, down to
      # max_scan_bytes from the end, and yields blocks of complete lines, newest
      # block first. A line cut by a chunk boundary is carried over to the next
      # (older) chunk; a line cut by the max_scan_bytes boundary is dropped.
      # The carried-over part of a line is kept as a list of chunks, so a long
      # line is not copied again for every chunk, and only its first
      # max_search_line_bytes bytes are kept.
      # @param file [File]
      # @param size [Integer] Size of the file when it was opened
      # @yieldparam text [String] Valid UTF-8 lines joined by "\n"
      # @yieldreturn [Boolean] true to stop reading
      # @return [Array(Integer, Boolean)] Bytes read and whether the start of the file was reached
      def scan_backwards(file, size)
        lower_bound = size - [ size, @max_scan_bytes ].min
        first_line_complete = lower_bound.zero? || file.pread(1, lower_bound - 1) == "\n"
        pos = content_end(file, size)
        carry = CarriedLine.new(@max_search_line_bytes)
        while pos > lower_bound
          length = [ @search_chunk_bytes, pos - lower_bound ].min
          pos -= length
          chunk = file.pread(length, pos)
          if pos > lower_bound || !first_line_complete
            newline = chunk.index("\n")
            if newline.nil?
              carry.prepend(chunk)
              next
            end
            data = carry.take(chunk.byteslice(newline + 1, chunk.bytesize))
            carry.prepend(chunk.byteslice(0, newline))
          else
            data = carry.take(chunk)
          end
          return [ size - pos, false ] if yield(to_utf8(data))
        end
        [ size - lower_bound, lower_bound.zero? ]
      end

      # The newline-free end of a line whose start has not been read yet, built
      # up from chunks read backwards. When the line grows beyond the limit, its
      # newest bytes are dropped so that its start, read last, is kept.
      class CarriedLine
        # @param max_bytes [Integer] Largest number of bytes kept
        def initialize(max_bytes)
          @max_bytes = max_bytes
          @chunks = []
          @bytes = 0
        end

        # Adds bytes that come before the ones kept so far.
        # @param bytes [String]
        def prepend(bytes)
          @chunks.unshift(bytes)
          @bytes += bytes.bytesize
          while @bytes > @max_bytes && @chunks.size > 1
            @bytes -= @chunks.pop.bytesize
          end
        end

        # Returns the given bytes followed by the bytes kept, and empties the line.
        # @param head [String] Bytes that come before the ones kept
        # @return [String]
        def take(head)
          text = head + @chunks.join
          @chunks = []
          @bytes = 0
          text
        end
      end
      private_constant :CarriedLine

      # Opens the file once for reading and translates I/O errors into
      # FileNotReadableError.
      # @yieldparam file [File] The opened file
      # @return [Object] The value of the block
      def open_file
        File.open(@path, "rb") do |file|
          raise FileNotReadableError.new(@file_name, :not_readable) unless file.stat.file?

          yield file
        end
      rescue Errno::ENOENT
        raise FileNotReadableError.new(@file_name, :not_found)
      rescue SystemCallError, IOError
        raise FileNotReadableError.new(@file_name, :not_readable)
      end

      # Returns the offset where the line content ends: the newline that
      # terminates the last line is not the start of another line.
      # @param file [File]
      # @param size [Integer] Size of the file when it was opened
      # @return [Integer]
      def content_end(file, size)
        return 0 if size.zero?

        file.pread(1, size - 1) == "\n" ? size - 1 : size
      end

      # Builds the line objects of the last lines read by the tail.
      # @param raw_lines [Array<String>] Complete lines read, in file order
      # @param lines [Integer] Number of lines requested
      # @param reached_start [Boolean] Whether raw_lines start at the first line of the file
      # @return [Array<Hash>] Line objects, oldest first
      def tail_lines(raw_lines, lines, reached_start)
        selected = raw_lines.last(lines)
        selected.each_with_index.map do |raw, index|
          lines_from_end = selected.size - index
          line_number = reached_start ? raw_lines.size - lines_from_end + 1 : nil
          self.class.build_line(raw, lines_from_end, line_number)
        end
      end

      # @param name [Symbol] Argument name used in the error message
      # @param value [Object] The value given by the caller
      # @param range [Range] Accepted values
      # @raise [ArgumentError] If the value is not an integer in the range
      def validate_range(name, value, range)
        return if value.is_a?(Integer) && range.cover?(value)

        raise ArgumentError, "#{name} must be an integer in #{range}"
      end

      # @param bytes [String] Binary string
      # @return [String] UTF-8 string with invalid bytes replaced
      def to_utf8(bytes)
        bytes.dup.force_encoding(Encoding::UTF_8).scrub(REPLACEMENT_CHAR)
      end
    end
  end
end
