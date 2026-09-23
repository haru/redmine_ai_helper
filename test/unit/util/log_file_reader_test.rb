require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/util/log_file_reader"

class RedmineAiHelper::Util::LogFileReaderTest < ActiveSupport::TestCase
  Reader = RedmineAiHelper::Util::LogFileReader

  # Counts the bytes returned by File#pread while count_read_bytes runs.
  module PreadCounter
    class << self
      attr_accessor :bytes
    end

    def pread(*args)
      data = super
      PreadCounter.bytes += data.bytesize if PreadCounter.bytes
      data
    end
  end
  File.prepend(PreadCounter)

  # @return [Integer] Bytes read with File#pread while the block runs
  def count_read_bytes
    PreadCounter.bytes = 0
    yield
    PreadCounter.bytes
  ensure
    PreadCounter.bytes = nil
  end

  setup do
    @tmpdir = Dir.mktmpdir
  end

  teardown do
    FileUtils.remove_entry(@tmpdir)
  end

  # Writes the given bytes to a file in the temporary directory.
  # @return [String] the file path
  def write_log(content, name = "test.log")
    path = File.join(@tmpdir, name)
    File.binwrite(path, content)
    path
  end

  # Builds "line 1\nline 2\n..." with the given number of lines.
  def numbered_lines(count)
    (1..count).map { |i| "line #{i}\n" }.join
  end

  def contents(lines)
    lines.map { |line| line[:content] }
  end

  # Runs a search with the SystemTools defaults unless overridden.
  def run_search(path, keyword, case_sensitive: false, context_lines: 0, max_matches: 50, **reader_options)
    Reader.new(path, **reader_options).search(keyword: keyword, case_sensitive: case_sensitive,
                                              context_lines: context_lines, max_matches: max_matches)
  end

  def match_contents(result)
    match_lines(result, :content)
  end

  # Collects one attribute of the matching line of every match.
  def match_lines(result, key)
    result[:matches].map { |match| match[:line][key] }
  end

  context "tail" do
    should "return the last lines oldest first with lines_from_end when the start is not reached" do
      path = write_log(numbered_lines(10))
      result = Reader.new(path, tail_chunk_bytes: 16).tail(lines: 3)

      assert_equal [ "line 8", "line 9", "line 10" ], contents(result[:lines])
      assert_equal [ 3, 2, 1 ], result[:lines].pluck(:lines_from_end)
      assert_equal [ nil, nil, nil ], result[:lines].pluck(:line_number)
      assert_equal [ false, false, false ], result[:lines].pluck(:truncated)
      assert_equal "from_end_only", result[:line_numbering]
      assert_equal false, result[:empty]
      assert_equal "test.log", result[:file_name]
      assert_equal File.size(path), result[:file_size_bytes]
    end

    should "number lines from the start when the whole file was read" do
      path = write_log(numbered_lines(10))
      result = Reader.new(path).tail(lines: 3)

      assert_equal [ "line 8", "line 9", "line 10" ], contents(result[:lines])
      assert_equal [ 8, 9, 10 ], result[:lines].pluck(:line_number)
      assert_equal "from_start", result[:line_numbering]
    end

    should "return every line numbered from the start when the file has fewer lines than requested" do
      path = write_log(numbered_lines(5))
      result = Reader.new(path, tail_chunk_bytes: 16).tail(lines: 100)

      assert_equal (1..5).map { |i| "line #{i}" }, contents(result[:lines])
      assert_equal (1..5).to_a, result[:lines].pluck(:line_number)
      assert_equal [ 5, 4, 3, 2, 1 ], result[:lines].pluck(:lines_from_end)
      assert_equal "from_start", result[:line_numbering]
    end

    should "number lines from the start when the requested count equals the file length" do
      path = write_log(numbered_lines(5))
      result = Reader.new(path, tail_chunk_bytes: 16).tail(lines: 5)

      assert_equal 5, result[:lines].size
      assert_equal "from_start", result[:line_numbering]
      assert_equal 1, result[:lines].first[:line_number]
    end

    should "treat a last line without a trailing newline as a line" do
      path = write_log("first\nsecond\nlast without newline")
      result = Reader.new(path, tail_chunk_bytes: 16).tail(lines: 2)

      assert_equal [ "second", "last without newline" ], contents(result[:lines])
    end

    should "strip carriage returns of CRLF line endings" do
      path = write_log("one\r\ntwo\r\nthree\r\n")
      result = Reader.new(path).tail(lines: 2)

      assert_equal [ "two", "three" ], contents(result[:lines])
    end

    should "read a line longer than the chunk size" do
      long = "x" * 100
      path = write_log("short\n#{long}\nend\n")
      result = Reader.new(path, tail_chunk_bytes: 16).tail(lines: 2)

      assert_equal [ long, "end" ], contents(result[:lines])
    end

    should "read no more than max_tail_bytes of a line without newlines" do
      path = write_log("#{"a" * 1_000}#{"b" * 50}")
      result = nil
      read = count_read_bytes { result = Reader.new(path, max_tail_bytes: 100, tail_chunk_bytes: 32).tail(lines: 1) }

      assert_operator read, :<=, 100 + 2 # the tail plus the bytes probed at its ends
      assert_equal true, result[:byte_limit_reached]
      assert_equal 1, result[:lines].size
      line = result[:lines].first
      assert_equal true, line[:truncated]
      assert_equal 1, line[:lines_from_end]
      assert_nil line[:line_number]
      assert_equal "[start of line not read]… #{"a" * 50}#{"b" * 50}", line[:content]
      assert_equal "from_end_only", result[:line_numbering]
    end

    should "return the lines found within max_tail_bytes and the end of the cut line" do
      path = write_log("first\n#{"z" * 500}\nL3\nL4\n")
      result = Reader.new(path, max_tail_bytes: 20, tail_chunk_bytes: 8).tail(lines: 4)

      assert_equal true, result[:byte_limit_reached]
      assert_equal [ "[start of line not read]… #{"z" * 14}", "L3", "L4" ], contents(result[:lines])
      assert_equal [ 3, 2, 1 ], result[:lines].pluck(:lines_from_end)
      assert_equal [ true, false, false ], result[:lines].pluck(:truncated)
    end

    should "not mark the first line as cut when max_tail_bytes ends at a line start" do
      path = write_log("aaaa\nbbbb\ncccc\n")
      result = Reader.new(path, max_tail_bytes: 9).tail(lines: 5)

      assert_equal true, result[:byte_limit_reached]
      assert_equal [ "bbbb", "cccc" ], contents(result[:lines])
    end

    should "not report the byte limit when enough lines were found" do
      path = write_log(numbered_lines(10))
      result = Reader.new(path, max_tail_bytes: 20, tail_chunk_bytes: 4).tail(lines: 2)

      assert_equal false, result[:byte_limit_reached]
      assert_equal [ "line 9", "line 10" ], contents(result[:lines])
    end

    should "read only the chunks needed for the requested lines" do
      path = write_log(numbered_lines(10_000))
      read = count_read_bytes { Reader.new(path, tail_chunk_bytes: 64).tail(lines: 3) }

      assert_operator read, :<=, 64 + 2 # one chunk plus the bytes probed at its ends
    end

    should "reject a line count outside 1..MAX_TAIL_LINES" do
      path = write_log("a\n")
      [ 0, -1, Reader::MAX_TAIL_LINES + 1, "3", nil ].each do |lines|
        assert_raises(ArgumentError, lines.inspect) { Reader.new(path).tail(lines: lines) }
      end
    end

    should "return an empty result for an empty file" do
      path = write_log("")
      result = Reader.new(path).tail(lines: 100)

      assert_equal true, result[:empty]
      assert_equal [], result[:lines]
      assert_equal 0, result[:file_size_bytes]
    end

    should "not count the empty string after the final newline as a line" do
      path = write_log("a\nb\n")
      result = Reader.new(path).tail(lines: 100)

      assert_equal [ "a", "b" ], contents(result[:lines])
      assert_equal [ 2, 1 ], result[:lines].pluck(:lines_from_end)
    end

    should "keep empty lines in the middle of the file" do
      path = write_log("a\n\nb\n")
      result = Reader.new(path).tail(lines: 100)

      assert_equal [ "a", "", "b" ], contents(result[:lines])
    end

    should "replace invalid UTF-8 bytes" do
      path = write_log("\xFF\xFEabc\n".b)
      result = Reader.new(path).tail(lines: 1)

      assert_equal "��abc", result[:lines].first[:content]
      assert_predicate result[:lines].first[:content], :valid_encoding?
    end

    should "keep multibyte characters that straddle a chunk boundary" do
      text = "あいうえおかきくけこ\n" * 3
      path = write_log(text)
      result = Reader.new(path, tail_chunk_bytes: 7).tail(lines: 3)

      assert_equal [ "あいうえおかきくけこ" ] * 3, contents(result[:lines])
    end

    should "truncate lines longer than MAX_LINE_CHARS" do
      path = write_log("#{"a" * 2_001}\n#{"b" * 2_000}\n")
      result = Reader.new(path).tail(lines: 2)

      long, exact = result[:lines]
      assert_equal "#{"a" * 2_000} …[truncated 1 chars]", long[:content]
      assert_equal true, long[:truncated]
      assert_equal "b" * 2_000, exact[:content]
      assert_equal false, exact[:truncated]
    end

    should "read only up to the size the file had when it was opened" do
      path = write_log(numbered_lines(3))
      size_at_open = File.size(path)
      File.open(path, "a") { |f| f.write("appended\n") }
      File.any_instance.stubs(:size).returns(size_at_open)

      result = Reader.new(path).tail(lines: 100)

      assert_equal [ "line 1", "line 2", "line 3" ], contents(result[:lines])
      assert_equal size_at_open, result[:file_size_bytes]
    end

    should "raise FileNotReadableError with the file name only when the file does not exist" do
      path = File.join(@tmpdir, "missing.log")
      error = assert_raises(Reader::FileNotReadableError) { Reader.new(path).tail(lines: 1) }

      assert_equal :not_found, error.reason
      assert_equal "missing.log", error.file_name
      assert_includes error.message, "missing.log"
      assert_not_includes error.message, @tmpdir
    end

    should "raise FileNotReadableError when the file cannot be read" do
      skip "root can read any file" if Process.uid.zero?
      path = write_log("secret\n")
      File.chmod(0o000, path)

      error = assert_raises(Reader::FileNotReadableError) { Reader.new(path).tail(lines: 1) }
      assert_equal :not_readable, error.reason
      assert_match(/cannot be read/, error.message)
      assert_not_includes error.message, @tmpdir
    end

    should "raise FileNotReadableError when the path is a directory" do
      error = assert_raises(Reader::FileNotReadableError) { Reader.new(@tmpdir).tail(lines: 1) }

      assert_equal :not_readable, error.reason
    end
  end

  context "search" do
    should "return matching lines oldest first and describe the scan" do
      path = write_log("alpha\nNoMethodError one\nbeta\nNoMethodError two\ngamma\n")
      result = run_search(path, "NoMethodError")

      assert_equal [ "NoMethodError one", "NoMethodError two" ], match_contents(result)
      assert_equal [ 2, 4 ], match_lines(result, :line_number)
      assert_equal [ 4, 2 ], match_lines(result, :lines_from_end)
      assert_equal 2, result[:match_count]
      assert_equal false, result[:truncated]
      assert_equal true, result[:scanned_whole_file]
      assert_equal "from_start", result[:line_numbering]
      assert_equal File.size(path), result[:scanned_bytes]
      assert_equal File.size(path), result[:file_size_bytes]
      assert_equal "test.log", result[:file_name]
      assert_equal "NoMethodError", result[:keyword]
      assert_equal false, result[:case_sensitive]
      assert_equal 0, result[:context_lines]
      assert_equal 50, result[:max_matches]
      assert_equal [ [], [] ], result[:matches].pluck(:before)
      assert_equal [ [], [] ], result[:matches].pluck(:after)
    end

    should "ignore case unless case_sensitive is true" do
      path = write_log("ERROR upper\nerror lower\n")

      assert_equal [ "ERROR upper", "error lower" ], match_contents(run_search(path, "Error"))
      assert_equal [], match_contents(run_search(path, "Error", case_sensitive: true))
      assert_equal [ "error lower" ], match_contents(run_search(path, "error", case_sensitive: true))
    end

    should "treat regular expression characters literally" do
      path = write_log("abc\na.c\nfoo(bar*\n.*\n")

      assert_equal [ "a.c" ], match_contents(run_search(path, "a.c"))
      assert_equal [ "foo(bar*" ], match_contents(run_search(path, "(bar*"))
      assert_equal [ ".*" ], match_contents(run_search(path, ".*"))
    end

    should "return no matches without raising when nothing matches" do
      path = write_log("alpha\nbeta\n")
      result = run_search(path, "missing")

      assert_equal 0, result[:match_count]
      assert_equal [], result[:matches]
      assert_equal false, result[:truncated]
    end

    should "return no matches for an empty file" do
      result = run_search(write_log(""), "anything")

      assert_equal 0, result[:match_count]
      assert_equal [], result[:matches]
      assert_equal 0, result[:file_size_bytes]
    end

    should "attach context lines oldest first and keep overlapping context" do
      path = write_log("l1\nl2 HIT\nl3\nl4\nl5 HIT\nl6\n")
      result = run_search(path, "HIT", context_lines: 2)

      first, second = result[:matches]
      assert_equal [ "l1" ], contents(first[:before])
      assert_equal "l2 HIT", first[:line][:content]
      assert_equal [ "l3", "l4" ], contents(first[:after])
      assert_equal [ "l3", "l4" ], contents(second[:before])
      assert_equal "l5 HIT", second[:line][:content]
      assert_equal [ "l6" ], contents(second[:after])
      assert_equal [ 3, 4 ], second[:before].pluck(:line_number)
      assert_equal [ 6 ], second[:after].pluck(:line_number)
    end

    should "not truncate when the matches equal max_matches" do
      path = write_log("HIT 1\nx\nHIT 2\nx\nHIT 3\n")
      result = run_search(path, "HIT", max_matches: 3)

      assert_equal 3, result[:match_count]
      assert_equal false, result[:truncated]
      assert_equal true, result[:scanned_whole_file]
    end

    should "return the newest max_matches matches and stop when there are more" do
      path = write_log("HIT 1\nx\nHIT 2\nx\nHIT 3\n")
      result = run_search(path, "HIT", max_matches: 2)

      assert_equal [ "HIT 2", "HIT 3" ], match_contents(result)
      assert_equal 2, result[:match_count]
      assert_equal true, result[:truncated]
      assert_equal false, result[:scanned_whole_file]
      assert_equal "from_end_only", result[:line_numbering]
      assert_equal [ nil, nil ], match_lines(result, :line_number)
      assert_equal [ 3, 1 ], match_lines(result, :lines_from_end)
    end

    should "fill the before context of the oldest returned match after the limit is reached" do
      path = write_log("c1\nHIT 1\nc2\nHIT 2\nHIT 3\n")
      result = run_search(path, "HIT", max_matches: 2, context_lines: 2)

      oldest = result[:matches].first
      assert_equal "HIT 2", oldest[:line][:content]
      assert_equal [ "HIT 1", "c2" ], contents(oldest[:before])
      assert_equal true, result[:truncated]
    end

    should "stop at max_scan_bytes and skip the incomplete line at the boundary" do
      content = "KEYWORD aaaa\n#{"bbbb\n" * 4}"
      path = write_log(content)
      result = run_search(path, "KEYWORD", max_scan_bytes: 25)

      assert_equal 0, result[:match_count]
      assert_equal 25, result[:scanned_bytes]
      assert_equal false, result[:scanned_whole_file]
      assert_equal "from_end_only", result[:line_numbering]
      assert_equal content.bytesize, result[:file_size_bytes]
    end

    should "include the first line when max_scan_bytes ends exactly at a line start" do
      path = write_log("KEYWORD aaaa\n#{"bbbb\n" * 4}")
      result = run_search(path, "bbbb", max_scan_bytes: 20)

      assert_equal 4, result[:match_count]
      assert_equal false, result[:scanned_whole_file]
      assert_equal [ 4, 3, 2, 1 ], match_lines(result, :lines_from_end)
    end

    should "find the same matches whatever the chunk size" do
      lines = (1..40).map { |i| i % 7 == 0 ? "row #{i} NEEDLE #{"z" * (i % 5)}" : "row #{i} #{"y" * (i % 11)}" }
      path = write_log(lines.join("\n") + "\n")
      [ 0, 1, 3 ].each do |context_lines|
        expected = run_search(path, "needle", context_lines: context_lines)
        assert_equal 5, expected[:match_count]

        [ 1, 3, 7, 32, 64 ].each do |chunk|
          result = run_search(path, "needle", context_lines: context_lines, search_chunk_bytes: chunk)
          assert_equal expected, result, "chunk size #{chunk}, context #{context_lines}"
        end
      end
    end

    should "replace invalid UTF-8 and truncate long lines in matches and context" do
      long_match = "KEY #{"a" * 2_100}"
      long_after = "z" * 2_500
      path = write_log("\xFFbefore\n#{long_match}\n#{long_after}\n".b)
      result = run_search(path, "KEY", context_lines: 1)

      match = result[:matches].first
      assert_equal "\uFFFDbefore", match[:before].first[:content]
      assert_equal true, match[:line][:truncated]
      assert match[:line][:content].start_with?("KEY ")
      assert match[:line][:content].end_with?(" …[truncated 104 chars]")
      assert_equal true, match[:after].first[:truncated]
    end

    should "match a non-ASCII keyword" do
      path = write_log("エラーが発生しました\n正常\n")

      assert_equal [ "エラーが発生しました" ], match_contents(run_search(path, "エラー"))
    end

    should "stop reading once more than max_matches lines matched" do
      path = write_log("HIT\n" * 1_000)
      result = run_search(path, "HIT", max_matches: 2, search_chunk_bytes: 16)

      assert_equal true, result[:truncated]
      assert_equal false, result[:scanned_whole_file]
      assert_operator result[:scanned_bytes], :<, 64
    end

    should "fill context across chunk boundaries after the limit is reached" do
      lines = (1..30).map { |i| i % 4 == 0 ? "row #{i} HIT" : "row #{i}" }
      path = write_log(lines.join("\n") + "\n")
      expected = run_search(path, "HIT", max_matches: 2, context_lines: 2).except(:scanned_bytes)
      assert_equal true, expected[:truncated]

      [ 1, 5, 16 ].each do |chunk|
        result = run_search(path, "HIT", max_matches: 2, context_lines: 2, search_chunk_bytes: chunk)
        assert_equal expected, result.except(:scanned_bytes), "chunk size #{chunk}"
      end
    end

    should "find a keyword at the start of a line longer than the chunk size" do
      path = write_log("before\nKEY #{"x" * 200}\nafter\n")

      [ 8, 1_024 ].each do |chunk|
        result = run_search(path, "KEY", search_chunk_bytes: chunk)
        assert_equal 1, result[:match_count], "chunk size #{chunk}"
        assert result[:matches].first[:line][:content].start_with?("KEY x")
        assert_equal 2, result[:matches].first[:line][:lines_from_end]
      end
    end

    should "keep only the first max_search_line_bytes of a very long line" do
      path = write_log("KEY #{"x" * 1_000} TAIL\nlast\n")

      head = run_search(path, "KEY", search_chunk_bytes: 16, max_search_line_bytes: 64)
      assert_equal 1, head[:match_count]
      assert_operator head[:matches].first[:line][:content].bytesize, :<=, 64 + 16

      tail = run_search(path, "TAIL", search_chunk_bytes: 16, max_search_line_bytes: 64)
      assert_equal 0, tail[:match_count]
      assert_equal true, tail[:scanned_whole_file]
    end

    should "reject an empty keyword and out-of-range limits" do
      path = write_log("a\n")
      assert_raises(ArgumentError) { run_search(path, "") }
      assert_raises(ArgumentError) { run_search(path, nil) }
      assert_raises(ArgumentError) { run_search(path, "a", max_matches: 0) }
      assert_raises(ArgumentError) { run_search(path, "a", max_matches: Reader::MAX_MATCHES_LIMIT + 1) }
      assert_raises(ArgumentError) { run_search(path, "a", context_lines: -1) }
      assert_raises(ArgumentError) { run_search(path, "a", context_lines: Reader::MAX_CONTEXT_LINES + 1) }
    end

    should "raise FileNotReadableError when the file does not exist" do
      error = assert_raises(Reader::FileNotReadableError) { run_search(File.join(@tmpdir, "gone.log"), "x") }

      assert_equal :not_found, error.reason
    end
  end

  context "new" do
    should "reject a limit or chunk size that is not a positive integer" do
      %i[max_scan_bytes max_tail_bytes max_search_line_bytes tail_chunk_bytes search_chunk_bytes].each do |name|
        [ 0, -1, nil, "8" ].each do |value|
          assert_raises(ArgumentError, "#{name}: #{value.inspect}") { Reader.new("x.log", name => value) }
        end
      end
    end
  end

  context "info" do
    should "return the file name, size and modification time" do
      path = write_log("hello\n", "production.log")
      result = Reader.new(path).info

      assert_equal "production.log", result[:file_name]
      assert_equal 6, result[:size_bytes]
      assert_equal File.mtime(path).iso8601, result[:updated_at]
      assert_not_includes result.to_json, @tmpdir
    end

    should "raise FileNotReadableError when the file does not exist" do
      error = assert_raises(Reader::FileNotReadableError) { Reader.new(File.join(@tmpdir, "gone.log")).info }

      assert_equal :not_found, error.reason
      assert_not_includes error.message, @tmpdir
    end

    should "raise FileNotReadableError when the file cannot be read" do
      skip "root can read any file" if Process.uid.zero?
      path = write_log("secret\n")
      File.chmod(0o000, path)

      error = assert_raises(Reader::FileNotReadableError) { Reader.new(path).info }
      assert_equal :not_readable, error.reason
    end
  end
end
