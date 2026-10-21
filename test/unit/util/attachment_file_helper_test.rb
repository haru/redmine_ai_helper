require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/util/attachment_file_helper"

# Redmine before 7.0 has no Markdownizer. The tests mock attachments that report a Markdown
# preview, so the production code still reads the output limit constant; provide a stand-in
# with Redmine 7.0's default (100 KiB) there.
unless defined?(Redmine::Markdownizer)
  module Redmine::Markdownizer
    MAX_OUTPUT_SIZE = 102_400
  end
end

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

  # Helper to create a mock Office document attachment backed by a real temporary file.
  # Without +previewable+ the mock does not respond to markdownized_previewable?, which
  # represents a Redmine 6.x attachment (mocha's respond_to? is false for unstubbed methods).
  # +content+ is the Markdown that Redmine's markdownized_preview_content returns (binary), or nil.
  def office_attachment(filename, previewable: nil, content: nil, id: 7, filesize: nil)
    attachment = real_attachment(filename, "office bytes")
    attachment.stubs(:id).returns(id)
    attachment.stubs(:filesize).returns(filesize || 1.megabyte)
    unless previewable.nil?
      attachment.stubs(:markdownized_previewable?).returns(previewable)
      attachment.stubs(:markdownized_preview_content).returns(content&.b)
    end
    attachment
  end

  # Redmine's output size limit for the Markdown conversion (a stand-in before Redmine 7.0).
  def max_output_size
    Redmine::Markdownizer::MAX_OUTPUT_SIZE
  end

  # Runs the block with Redmine's output size limit replaced, as configured by
  # markdownized_preview_max_output_size in configuration.yml.
  def with_max_output_size(size)
    original = max_output_size
    silence_warnings { Redmine::Markdownizer.const_set(:MAX_OUTPUT_SIZE, size) }
    yield
  ensure
    silence_warnings { Redmine::Markdownizer.const_set(:MAX_OUTPUT_SIZE, original) } if original
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
      # chat.ask(text, with: paths) wraps the paths into RubyLLM::Attachment objects
      attachments = RubyLLM::Message.new(role: :user, content: "question", attachments: result).attachments

      assert_equal 3, attachments.size
      # Converted attachments keep the original filename, so they are embedded as text
      assert_equal [ :text, :text ], attachments.first(2).map(&:type)
      payload = attachments.map(&:for_llm)
      assert_nothing_raised { JSON.generate(payload) }
      assert_includes payload[0], "# 見出し"
      assert_includes payload[1], "puts '日本語'"
    end
  end

  context "supported_attachment_paths with Office documents" do
    should "send the Markdown converted by Redmine as an attachment named after the original file" do
      att = office_attachment("x.docx", previewable: true, content: "# Title\n\nbody")
      RedmineAiHelper::CustomLogger.instance.expects(:warn).never
      RedmineAiHelper::CustomLogger.instance.expects(:info).never

      result = @helper.supported_attachment_paths(container_with(att))

      assert_equal 1, result.size
      assert_kind_of RubyLLM::Attachment, result.first
      assert_equal "x.docx.md", result.first.filename
      assert_equal "text/markdown", result.first.mime_type
      assert_equal "# Title\n\nbody", result.first.content
      assert_not_includes result.first.content, att.diskfile
    end

    should "keep the order of attachments and send images as disk paths" do
      doc = office_attachment("x.docx", previewable: true, content: "body")
      png = real_attachment("a.png", "png bytes")

      result = @helper.supported_attachment_paths(container_with(doc, png))

      assert_equal 2, result.size
      assert_kind_of RubyLLM::Attachment, result[0]
      assert_equal png.diskfile, result[1]
    end

    should "not convert when attachment sending is disabled" do
      @setting.update!(attachment_send_enabled: false)
      att = office_attachment("x.docx", previewable: true, content: "body")
      att.expects(:markdownized_preview_content).never

      assert_equal [], @helper.supported_attachment_paths(container_with(att))
    end

    should "not convert files above the maximum size of the original file" do
      @setting.update!(attachment_max_size_mb: 2)
      att = office_attachment("x.docx", previewable: true, content: "body", filesize: 3.megabytes)
      att.expects(:markdownized_preview_content).never

      assert_equal [], @helper.supported_attachment_paths(container_with(att))
    end

    should "not convert files that do not exist on disk" do
      att = office_attachment("x.docx", previewable: true, content: "body")
      FileUtils.rm_f(att.diskfile)
      att.expects(:markdownized_preview_content).never

      assert_equal [], @helper.supported_attachment_paths(container_with(att))
    end

    should "append .md to the original filename with an upper-case extension" do
      att = office_attachment("X.DOCX", previewable: true, content: "body")

      result = @helper.supported_attachment_paths(container_with(att))

      assert_equal "X.DOCX.md", result.first.filename
    end

    should "not ask Redmine about files with an existing supported extension" do
      txt = real_attachment("a.txt", "plain")
      txt.expects(:markdownized_previewable?).never
      txt.expects(:markdownized_preview_content).never
      png = real_attachment("a.png", "png bytes")
      png.expects(:markdownized_previewable?).never

      result = @helper.supported_attachment_paths(container_with(txt, png))

      assert_equal [ txt.diskfile, png.diskfile ], result
    end

    should "add a notice for each kind of image reference" do
      [ "![](media/a.png)", "<img src=\"a.png\" />", "<IMG SRC=a.png>" ].each do |ref|
        att = office_attachment("x.docx", previewable: true, content: "text #{ref} more")

        content = @helper.supported_attachment_paths(container_with(att)).first.content

        assert content.start_with?("text #{ref} more\n\n"), "no separator for #{ref}"
        assert_includes content, "images and figures inside the Office document \"x.docx\"", "no notice for #{ref}"
      end
    end

    should "not add a notice when there is no image reference" do
      att = office_attachment("x.docx", previewable: true, content: "just text")

      assert_equal "just text", @helper.supported_attachment_paths(container_with(att)).first.content
    end

    should "not treat links or other tags as image references" do
      [ "[text](http://example.com/a.png)", "<imgx src=a.png>", "<image src=a.png>", "! [a](b.png)" ].each do |ref|
        att = office_attachment("x.docx", previewable: true, content: "text #{ref}")

        assert_equal "text #{ref}", @helper.supported_attachment_paths(container_with(att)).first.content, "notice added for #{ref}"
      end
    end

    should "add the no-text notice when only an HTML image tag remains" do
      att = office_attachment("x.docx", previewable: true, content: "<img src=\"media/image1.png\" />\n")

      content = @helper.supported_attachment_paths(container_with(att)).first.content

      assert_includes content, "images and figures inside"
      assert_includes content, "contains no text"
    end

    should "add the no-text notice after the image notice when only image references remain" do
      att = office_attachment("x.docx", previewable: true, content: "![](media/image1.png)\n")

      content = @helper.supported_attachment_paths(container_with(att)).first.content
      images = content.index("images and figures inside")
      no_text = content.index("contains no text")

      assert content.start_with?("![](media/image1.png)\n\n")
      assert images && no_text && images < no_text
      assert_not_includes content, "could not be converted"
    end

    should "add only the no-text notice for an empty conversion result" do
      att = office_attachment("x.docx", previewable: true, content: "")

      content = @helper.supported_attachment_paths(container_with(att)).first.content

      assert_includes content, "contains no text"
      assert_not_includes content, "images and figures inside"
      assert_not_includes content, "could not be converted"
    end

    should "share Redmine's conversion cache without running Pandoc again" do
      skip "Redmine's Markdown preview is not available" unless Attachment.method_defined?(:markdownized_preview_content)

      Redmine::Markdownizer.stubs(:available?).returns(true)
      Redmine::Markdownizer.stubs(:markdownizable_extensions).returns([ ".docx" ])
      att = Attachment.new(file: mock_file(original_filename: "cached.docx", content_type: "application/octet-stream", size: 12), author: User.find(2))
      att.container = Issue.find(1)
      att.save!
      FileUtils.mkdir_p(File.dirname(att.markdownized_preview_cache_path))
      File.binwrite(att.markdownized_preview_cache_path, "# Cached\n\ntext")
      Process.expects(:spawn).never

      begin
        result = @helper.supported_attachment_paths(container_with(att))

        assert_equal "# Cached\n\ntext", result.first.content
      ensure
        FileUtils.rm_f(att.markdownized_preview_cache_path)
        att.destroy
      end
    end
  end

  context "attachment_file_type for Office documents" do
    should "return 'document' when Redmine can convert the file" do
      att = office_attachment("x.docx", previewable: true, content: "body")

      assert_equal "document", @helper.send(:attachment_file_type, att)
    end

    should "keep the existing types without asking Redmine" do
      png = mock_attachment("a.png")
      png.expects(:markdownized_previewable?).never
      rb = mock_attachment("a.rb")
      rb.expects(:markdownized_previewable?).never

      assert_equal "image", @helper.send(:attachment_file_type, png)
      assert_equal "code", @helper.send(:attachment_file_type, rb)
    end
  end

  context "supported_attachment_paths without Redmine's Markdown preview" do
    should "ignore Office documents when the attachment has no markdownized_previewable? (Redmine 6.x)" do
      doc = office_attachment("x.docx")
      txt = real_attachment("a.txt", "plain")

      result = nil
      assert_nothing_raised { result = @helper.supported_attachment_paths(container_with(doc, txt)) }

      assert_equal [ txt.diskfile ], result
      assert_nil @helper.send(:attachment_file_type, doc)
    end

    should "not return or convert documents that Redmine reports as not convertible" do
      docx = office_attachment("x.docx", previewable: false)
      docx.expects(:markdownized_preview_content).never
      xlsx = office_attachment("x.xlsx", previewable: false)
      xlsx.expects(:markdownized_preview_content).never

      assert_equal [], @helper.supported_attachment_paths(container_with(docx, xlsx))
      assert_nil @helper.send(:attachment_file_type, docx)
    end

    should "return only the convertible documents when mixed with non-convertible ones" do
      docx = office_attachment("x.docx", previewable: true, content: "body")
      xlsx = office_attachment("x.xlsx", previewable: false)

      result = @helper.supported_attachment_paths(container_with(docx, xlsx))

      assert_equal [ "x.docx.md" ], result.map(&:filename)
    end
  end

  context "supported_attachment_paths with Office documents that cannot be fully converted" do
    should "send only a notice and log a warning when the conversion fails" do
      att = office_attachment("x.docx", previewable: true, content: nil, id: 55)
      RedmineAiHelper::CustomLogger.instance.expects(:warn).with { |m| m.include?("55") && m.include?("x.docx") }.once

      result = @helper.supported_attachment_paths(container_with(att))

      assert_equal 1, result.size
      assert_kind_of RubyLLM::Attachment, result.first
      assert_equal "x.docx.md", result.first.filename
      assert_equal "text/markdown", result.first.mime_type
      assert_equal 1, result.first.content.scan("could not be converted to text").size
      assert result.first.content.start_with?("[Attachment notice]")
      assert_not_includes result.first.content, att.diskfile
    end

    should "keep the other attachments and their order when a conversion fails" do
      failed = office_attachment("x.docx", previewable: true, content: nil)
      txt = real_attachment("a.txt", "plain")
      RedmineAiHelper::CustomLogger.instance.stubs(:warn)

      result = @helper.supported_attachment_paths(container_with(failed, txt))

      assert_equal 2, result.size
      assert_kind_of RubyLLM::Attachment, result[0]
      assert_equal txt.diskfile, result[1]
    end

    should "add the truncation notice and log info when the result reaches the output limit" do
      att = office_attachment("x.docx", previewable: true, content: "a" * max_output_size, id: 56)
      RedmineAiHelper::CustomLogger.instance.expects(:info).with { |m| m.include?("56") && m.include?("x.docx") }.once

      content = @helper.supported_attachment_paths(container_with(att)).first.content

      assert content.start_with?(("a" * max_output_size) + "\n\n")
      assert_includes content, "was cut off at the size limit"
    end

    should "not add the truncation notice below the output limit" do
      att = office_attachment("x.docx", previewable: true, content: "a" * (max_output_size - 1))
      RedmineAiHelper::CustomLogger.instance.expects(:info).never

      content = @helper.supported_attachment_paths(container_with(att)).first.content

      assert_equal "a" * (max_output_size - 1), content
    end

    should "remove only the incomplete trailing bytes of a character cut at the output limit" do
      RedmineAiHelper::CustomLogger.instance.stubs(:info)
      { "😀" => [ 1, 2, 3 ], "あ" => [ 1, 2 ], "é" => [ 1 ] }.each do |char, cuts|
        cuts.each do |n|
          body = "日本語 " + ("a" * (max_output_size - "日本語 ".bytesize - n))
          att = office_attachment("x.docx", previewable: true, content: body.b + char.b.byteslice(0, n))

          content = @helper.supported_attachment_paths(container_with(att)).first.content

          assert content.valid_encoding?, "invalid for #{char.inspect} cut at #{n}"
          assert content.start_with?(body + "\n\n"), "unexpected content for #{char.inspect} cut at #{n}"
          assert_not_includes content, "�"
        end
      end
    end

    should "raise EncodingError for an incomplete last character below the output limit" do
      att = office_attachment("x.docx", previewable: true, content: "abc\xE3\x81".b, id: 79)

      error = assert_raises(EncodingError) { @helper.supported_attachment_paths(container_with(att)) }

      assert_includes error.message, "79"
    end

    should "raise EncodingError for an invalid last byte that does not start a character" do
      RedmineAiHelper::CustomLogger.instance.stubs(:info)
      att = office_attachment("x.docx", previewable: true, content: ("a" * (max_output_size - 1)) + "\xFF".b)

      assert_raises(EncodingError) { @helper.supported_attachment_paths(container_with(att)) }
    end

    should "raise EncodingError when a lead byte is followed by a byte that does not continue it" do
      RedmineAiHelper::CustomLogger.instance.stubs(:info)
      att = office_attachment("x.docx", previewable: true, content: ("a" * (max_output_size - 2)) + "\xE3A".b)

      assert_raises(EncodingError) { @helper.supported_attachment_paths(container_with(att)) }
    end

    should "raise EncodingError for invalid results shorter than an incomplete character" do
      RedmineAiHelper::CustomLogger.instance.stubs(:info)
      with_max_output_size(1) do
        [ "\xFF", "\xE3\xE3" ].each do |bytes|
          att = office_attachment("x.docx", previewable: true, content: bytes.b)

          assert_raises(EncodingError, "for #{bytes.inspect}") { @helper.supported_attachment_paths(container_with(att)) }
        end
      end
    end

    should "raise TypeError when Redmine returns neither a String nor nil" do
      att = office_attachment("x.docx", previewable: true, content: "body", id: 80)
      att.stubs(:markdownized_preview_content).returns(:unexpected)

      error = assert_raises(TypeError) { @helper.supported_attachment_paths(container_with(att)) }

      assert_includes error.message, "80"
      assert_includes error.message, "Symbol"
    end

    should "judge truncation on the size before the incomplete bytes are removed" do
      body = "a" * (max_output_size - 1)
      att = office_attachment("x.docx", previewable: true, content: body.b + "\xE3".b)

      content = @helper.supported_attachment_paths(container_with(att)).first.content

      assert content.start_with?(body + "\n\n")
      assert content.valid_encoding?
      assert_includes content, "was cut off at the size limit"
    end

    should "raise EncodingError for an invalid byte that is not at the end" do
      att = office_attachment("x.docx", previewable: true, content: "ab\xFFcd".b, id: 77)

      error = assert_raises(EncodingError) { @helper.supported_attachment_paths(container_with(att)) }

      assert_includes error.message, "77"
    end

    should "raise EncodingError when more than three trailing bytes are invalid" do
      att = office_attachment("x.docx", previewable: true, content: "abc\xFF\xFF\xFF\xFF".b, id: 78)

      error = assert_raises(EncodingError) { @helper.supported_attachment_paths(container_with(att)) }

      assert_includes error.message, "78"
    end

    should "order the notices truncation, images, no text" do
      content_in = "![](a.png)".ljust(max_output_size, " ")
      att = office_attachment("x.docx", previewable: true, content: content_in)
      RedmineAiHelper::CustomLogger.instance.stubs(:info)

      content = @helper.supported_attachment_paths(container_with(att)).first.content
      cut = content.index("was cut off at the size limit")
      images = content.index("images and figures inside")
      no_text = content.index("contains no text")

      assert content.start_with?(content_in + "\n\n")
      assert cut && images && no_text && cut < images && images < no_text
    end

    should "send the notices in Japanese when the locale is ja" do
      RedmineAiHelper::CustomLogger.instance.stubs(:warn)
      RedmineAiHelper::CustomLogger.instance.stubs(:info)
      failed = office_attachment("x.docx", previewable: true, content: nil)
      full = office_attachment("y.docx", previewable: true, content: "![](a.png)".ljust(max_output_size, " "))
      empty = office_attachment("z.docx", previewable: true, content: "")

      result = I18n.with_locale(:ja) { @helper.supported_attachment_paths(container_with(failed, full, empty)) }

      assert_includes result[0].content, "テキストに変換できなかった"
      assert_includes result[1].content, "上限サイズで切り詰められ"
      assert_includes result[1].content, "画像や図"
      assert_includes result[2].content, "テキストが含まれていません"
    end
  end
end
