require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/util/attachment_file_helper"

class RedmineAiHelper::Util::AttachmentFileHelperTest < ActiveSupport::TestCase
  class TestClass
    include RedmineAiHelper::Util::AttachmentFileHelper
  end

  setup do
    @helper = TestClass.new
    AiHelperSetting.delete_all
    @setting = AiHelperSetting.find_or_create
    @setting.update!(attachment_send_enabled: true, attachment_max_size_mb: 100)
    @tmpdirs = []
  end

  teardown do
    @tmpdirs.each { |d| FileUtils.remove_entry(d, true) }
  end

  # Helper to create a mock attachment with a given filename
  def mock_attachment(filename, disk_path: nil, exists: true, filesize: 1.megabyte)
    attachment = mock("attachment_#{filename}")
    attachment.stubs(:filename).returns(filename)
    disk_path ||= "/path/to/files/#{filename}"
    attachment.stubs(:diskfile).returns(disk_path)
    attachment.stubs(:filesize).returns(filesize)
    attachment.stubs(:id).returns(1)
    File.stubs(:exist?).with(disk_path).returns(exists)
    File.stubs(:binread).with(disk_path).returns(+"plain utf-8 text")
    attachment
  end

  # Helper to create an attachment backed by a real temporary file
  def real_attachment(filename, bytes)
    dir = Dir.mktmpdir
    @tmpdirs << dir
    path = File.join(dir, "disk_file")
    File.binwrite(path, bytes)
    attachment = mock("real_attachment_#{filename}")
    attachment.stubs(:id).returns(42)
    attachment.stubs(:filename).returns(filename)
    attachment.stubs(:diskfile).returns(path)
    attachment.stubs(:filesize).returns(bytes.bytesize)
    attachment
  end

  def container_with(*attachments)
    container = mock("container")
    container.stubs(:respond_to?).with(:attachments).returns(true)
    container.stubs(:attachments).returns(attachments)
    container
  end

  def with_encodings(value)
    Setting.stubs(:repositories_encodings).returns(value)
  end

  context "supported_attachment_paths" do
    should "return disk paths for image attachments" do
      attachment = mock_attachment("image.png")

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([ attachment ])

      result = @helper.supported_attachment_paths(container)

      assert_equal [ "/path/to/files/image.png" ], result
    end

    should "return disk paths for various image formats" do
      %w[jpg jpeg png gif webp bmp].each do |ext|
        attachment = mock_attachment("image.#{ext}")

        container = mock("container")
        container.stubs(:respond_to?).with(:attachments).returns(true)
        container.stubs(:attachments).returns([ attachment ])

        result = @helper.supported_attachment_paths(container)

        assert_equal [ "/path/to/files/image.#{ext}" ], result, "Failed for extension: #{ext}"
      end
    end

    should "return disk paths for PDF files" do
      attachment = mock_attachment("document.pdf")

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([ attachment ])

      result = @helper.supported_attachment_paths(container)

      assert_equal [ "/path/to/files/document.pdf" ], result
    end

    should "return disk paths for text and document files" do
      %w[txt md csv json xml].each do |ext|
        attachment = mock_attachment("file.#{ext}")

        container = mock("container")
        container.stubs(:respond_to?).with(:attachments).returns(true)
        container.stubs(:attachments).returns([ attachment ])

        result = @helper.supported_attachment_paths(container)

        assert_equal [ "/path/to/files/file.#{ext}" ], result, "Failed for extension: #{ext}"
      end
    end

    should "return disk paths for code files" do
      %w[rb py js html css ts tsx jsx java c cpp h hpp cs go rs sh bash zsh yml yaml toml].each do |ext|
        attachment = mock_attachment("code.#{ext}")

        container = mock("container")
        container.stubs(:respond_to?).with(:attachments).returns(true)
        container.stubs(:attachments).returns([ attachment ])

        result = @helper.supported_attachment_paths(container)

        assert_equal [ "/path/to/files/code.#{ext}" ], result, "Failed for extension: #{ext}"
      end
    end

    should "return disk paths for audio files" do
      %w[mp3 wav m4a ogg flac].each do |ext|
        attachment = mock_attachment("audio.#{ext}")

        container = mock("container")
        container.stubs(:respond_to?).with(:attachments).returns(true)
        container.stubs(:attachments).returns([ attachment ])

        result = @helper.supported_attachment_paths(container)

        assert_equal [ "/path/to/files/audio.#{ext}" ], result, "Failed for extension: #{ext}"
      end
    end

    should "exclude unsupported file extensions" do
      supported = mock_attachment("image.png")
      exe_file = mock_attachment("malware.exe")
      zip_file = mock_attachment("archive.zip")
      mp4_file = mock_attachment("video.mp4")
      mov_file = mock_attachment("video.mov")

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([ supported, exe_file, zip_file, mp4_file, mov_file ])

      result = @helper.supported_attachment_paths(container)

      assert_equal [ "/path/to/files/image.png" ], result
    end

    should "exclude files that do not exist on disk" do
      existing = mock_attachment("existing.pdf")
      missing = mock_attachment("missing.pdf", exists: false)

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([ existing, missing ])

      result = @helper.supported_attachment_paths(container)

      assert_equal [ "/path/to/files/existing.pdf" ], result
    end

    should "return empty array when container has no attachments" do
      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([])

      result = @helper.supported_attachment_paths(container)

      assert_equal [], result
    end

    should "return empty array when container does not respond to attachments" do
      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(false)

      result = @helper.supported_attachment_paths(container)

      assert_equal [], result
    end

    should "return multiple file paths for mixed file types" do
      image = mock_attachment("screenshot.png")
      pdf = mock_attachment("report.pdf")
      code = mock_attachment("script.rb")

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([ image, pdf, code ])

      result = @helper.supported_attachment_paths(container)

      assert_equal [ "/path/to/files/screenshot.png", "/path/to/files/report.pdf", "/path/to/files/script.rb" ], result
    end

    should "handle case-insensitive extensions" do
      attachment = mock_attachment("IMAGE.PNG")

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([ attachment ])

      result = @helper.supported_attachment_paths(container)

      assert_equal [ "/path/to/files/IMAGE.PNG" ], result
    end
  end

  context "image_attachment_paths (backward compatibility alias)" do
    should "return the same result as supported_attachment_paths" do
      image = mock_attachment("image.png")
      pdf = mock_attachment("report.pdf")

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([ image, pdf ])

      supported_result = @helper.supported_attachment_paths(container)
      alias_result = @helper.image_attachment_paths(container)

      assert_equal supported_result, alias_result
    end
  end

  context "attachment_file_type" do
    should "return 'image' for image files" do
      %w[jpg jpeg png gif webp bmp].each do |ext|
        attachment = mock_attachment("file.#{ext}")

        assert_equal "image", @helper.send(:attachment_file_type, attachment), "Failed for extension: #{ext}"
      end
    end

    should "return 'audio' for audio files" do
      %w[mp3 wav m4a ogg flac].each do |ext|
        attachment = mock_attachment("file.#{ext}")

        assert_equal "audio", @helper.send(:attachment_file_type, attachment), "Failed for extension: #{ext}"
      end
    end

    should "return 'document' for document files" do
      %w[pdf txt md csv json xml].each do |ext|
        attachment = mock_attachment("file.#{ext}")

        assert_equal "document", @helper.send(:attachment_file_type, attachment), "Failed for extension: #{ext}"
      end
    end

    should "return 'code' for code files" do
      %w[rb py js html css ts tsx jsx java c cpp h hpp cs go rs sh bash zsh yml yaml toml].each do |ext|
        attachment = mock_attachment("file.#{ext}")

        assert_equal "code", @helper.send(:attachment_file_type, attachment), "Failed for extension: #{ext}"
      end
    end

    should "return nil for unsupported files" do
      %w[exe zip tar gz mp4 mov avi dll so].each do |ext|
        attachment = mock_attachment("file.#{ext}")

        assert_nil @helper.send(:attachment_file_type, attachment), "Expected nil for extension: #{ext}"
      end
    end
  end

  context "supported_file?" do
    should "return true for supported extensions" do
      %w[png pdf rb mp3 txt].each do |ext|
        attachment = mock_attachment("file.#{ext}")

        assert @helper.send(:supported_file?, attachment), "Expected true for extension: #{ext}"
      end
    end

    should "return false for unsupported extensions" do
      %w[exe zip mp4 tar dll].each do |ext|
        attachment = mock_attachment("file.#{ext}")

        assert_not @helper.send(:supported_file?, attachment), "Expected false for extension: #{ext}"
      end
    end
  end

  context "supported_attachment_paths with attachment settings" do
    should "return empty array when attachment_send_enabled is false" do
      @setting.update!(attachment_send_enabled: false)
      attachment = mock_attachment("image.png", filesize: 1.megabyte)

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([ attachment ])

      result = @helper.supported_attachment_paths(container)

      assert_equal [], result
    end

    should "return file paths when attachment_send_enabled is true" do
      @setting.update!(attachment_send_enabled: true, attachment_max_size_mb: 3)
      attachment = mock_attachment("image.png", filesize: 1.megabyte)

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([ attachment ])

      result = @helper.supported_attachment_paths(container)

      assert_equal [ "/path/to/files/image.png" ], result
    end

    should "exclude files exceeding attachment_max_size_mb" do
      @setting.update!(attachment_send_enabled: true, attachment_max_size_mb: 2)
      small_file = mock_attachment("small.png", filesize: 1.megabyte)
      large_file = mock_attachment("large.png", filesize: 3.megabytes)

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([ small_file, large_file ])

      result = @helper.supported_attachment_paths(container)

      assert_equal [ "/path/to/files/small.png" ], result
    end

    should "include files at exactly the max size limit" do
      @setting.update!(attachment_send_enabled: true, attachment_max_size_mb: 2)
      exact_file = mock_attachment("exact.png", filesize: 2.megabytes)

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([ exact_file ])

      result = @helper.supported_attachment_paths(container)

      assert_equal [ "/path/to/files/exact.png" ], result
    end

    should "combine size filtering with extension filtering" do
      @setting.update!(attachment_send_enabled: true, attachment_max_size_mb: 2)
      small_supported = mock_attachment("file.png", filesize: 1.megabyte)
      large_supported = mock_attachment("file2.png", filesize: 3.megabytes)
      small_unsupported = mock_attachment("file.exe", filesize: 1.megabyte)

      container = mock("container")
      container.stubs(:respond_to?).with(:attachments).returns(true)
      container.stubs(:attachments).returns([ small_supported, large_supported, small_unsupported ])

      result = @helper.supported_attachment_paths(container)

      assert_equal [ "/path/to/files/file.png" ], result
    end
  end

  context "supported_attachment_paths with non-UTF-8 text attachments" do
    should "convert a Shift_JIS .txt file using repositories_encodings" do
      with_encodings("utf-8,shift_jis,euc-jp")
      att = real_attachment("memo.txt", "日本語のテキスト".encode("Shift_JIS"))

      result = @helper.supported_attachment_paths(container_with(att))

      assert_equal 1, result.size
      assert_kind_of RubyLLM::Attachment, result.first
      assert_equal "日本語のテキスト", result.first.content
      assert result.first.content.valid_encoding?
      assert_equal "memo.txt", result.first.filename
    end

    should "convert an EUC-JP .md file" do
      with_encodings("utf-8,shift_jis,euc-jp")
      att = real_attachment("memo.md", "日本語のテキスト".encode("EUC-JP"))

      result = @helper.supported_attachment_paths(container_with(att))

      assert_equal "日本語のテキスト", result.first.content
    end

    should "convert CP932 text when cp932 is configured" do
      with_encodings("utf-8,cp932,euc-jp")
      text = "①番の～と髙橋さん"
      att = real_attachment("memo.txt", text.encode("CP932"))

      result = @helper.supported_attachment_paths(container_with(att))

      assert_equal text, result.first.content
    end

    should "skip unknown candidate encodings without raising" do
      with_encodings("bogus-enc,shift_jis")
      att = real_attachment("memo.txt", "日本語".encode("Shift_JIS"))

      result = @helper.supported_attachment_paths(container_with(att))

      assert_equal "日本語", result.first.content
    end

    should "produce content that can be serialized to JSON" do
      with_encodings("utf-8,shift_jis,euc-jp")
      att = real_attachment("memo.txt", "日本語".encode("Shift_JIS"))

      result = @helper.supported_attachment_paths(container_with(att))

      assert_nothing_raised { JSON.generate(content: result.first.content) }
    end

    should "send a notice when the file cannot be converted with the configured encodings" do
      with_encodings("utf-8,shift_jis,euc-jp")
      att = real_attachment("memo.txt", "①番の髙橋".encode("CP932"))
      RedmineAiHelper::CustomLogger.instance.expects(:warn).once

      result = @helper.supported_attachment_paths(container_with(att))

      assert_kind_of RubyLLM::Attachment, result.first
      assert_includes result.first.content, "memo.txt"
    end

    should "send a notice without the original bytes or disk path when no encoding is configured" do
      with_encodings("")
      bytes = "日本語".encode("Shift_JIS")
      att = real_attachment("memo.txt", bytes)
      RedmineAiHelper::CustomLogger.instance.expects(:warn).with { |m| m.include?("42") && m.include?("memo.txt") }.once

      result = @helper.supported_attachment_paths(container_with(att))

      content = result.first.content
      assert content.valid_encoding?
      assert_not_includes content, att.diskfile
      assert_includes content, "memo.txt"
      assert_equal "memo.txt", result.first.filename
    end

    should "keep order and count when mixing readable and unreadable files" do
      with_encodings("")
      utf8 = real_attachment("a.txt", "日本語")
      sjis = real_attachment("b.txt", "日本語".encode("Shift_JIS"))
      RedmineAiHelper::CustomLogger.instance.stubs(:warn)

      result = @helper.supported_attachment_paths(container_with(utf8, sjis))

      assert_equal 2, result.size
      assert_equal utf8.diskfile, result[0]
      assert_kind_of RubyLLM::Attachment, result[1]
    end

    should "return disk paths for UTF-8, ASCII and empty text regardless of encodings setting" do
      [ "", "shift_jis,utf-8" ].each do |enc|
        with_encodings(enc)
        RedmineAiHelper::CustomLogger.instance.expects(:warn).never
        atts = [ real_attachment("a.txt", "日本語"), real_attachment("b.rb", "puts 1"), real_attachment("c.txt", "") ]

        result = @helper.supported_attachment_paths(container_with(*atts))

        assert_equal atts.map(&:diskfile), result
      end
    end

    should "not read image, audio or PDF files" do
      %w[a.png a.mp3 a.pdf].each do |name|
        att = mock_attachment(name)
        File.expects(:binread).with(att.diskfile).never

        assert_equal [ att.diskfile ], @helper.supported_attachment_paths(container_with(att))
      end
    end

    should "not read files that are filtered out" do
      big = mock_attachment("big.txt", filesize: 200.megabytes)
      missing = mock_attachment("missing.txt", exists: false)
      other = mock_attachment("x.exe")
      disabled = mock_attachment("a.txt")
      # Declared after mock_attachment so it takes precedence over its binread stubs
      File.expects(:binread).never

      assert_equal [], @helper.supported_attachment_paths(container_with(big, missing, other))

      @setting.update!(attachment_send_enabled: false)
      assert_equal [], @helper.supported_attachment_paths(container_with(disabled))
    end

    should "send a Japanese notice when the locale is ja" do
      with_encodings("")
      att = real_attachment("memo.txt", "日本語".encode("Shift_JIS"))
      RedmineAiHelper::CustomLogger.instance.stubs(:warn)

      result = I18n.with_locale(:ja) { @helper.supported_attachment_paths(container_with(att)) }

      assert_includes result.first.content, "添付ファイルに関する注記"
      assert_includes result.first.content, "memo.txt"
    end

    should "produce sources that RubyLLM can serialize into a request" do
      with_encodings("utf-8,shift_jis,euc-jp")
      atts = [
        real_attachment("a.md", "# 見出し".encode("Shift_JIS")),
        real_attachment("b.rb", "puts '日本語'".encode("EUC-JP")),
        real_attachment("c.txt", "日本語")
      ]

      result = @helper.supported_attachment_paths(container_with(*atts))
      content = RubyLLM::Content.new("question", result)

      assert_equal 3, content.attachments.size
      # Converted attachments keep the original filename, so they are embedded as text
      assert_equal [ :text, :text ], content.attachments.first(2).map(&:type)
      payload = content.attachments.map(&:for_llm)
      assert_nothing_raised { JSON.generate(payload) }
      assert_includes payload[0], "# 見出し"
      assert_includes payload[1], "puts '日本語'"
    end
  end
end
