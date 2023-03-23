require 'fileutils'

module TmpFile
  def self.user_tmp(subdir = nil)
    if subdir
      File.join(ENV["HOME"],"/tmp/scout", subdir)
    else
      File.join(ENV["HOME"],"/tmp/scout")
    end
  end

  def self.tmpdir=(tmpdir)
    @tmpdir = tmpdir
  end

  def self.tmpdir
    @tmpdir ||= self.user_tmp('tmpfiles')
  end

  # Creates a random file name, with the given suffix and a random number
  # up to +max+
  def self.random_name(prefix = 'tmp-', max = 1_000_000_000)
    n = rand(max)
    prefix + n.to_s
  end

  # Creates a random filename in the temporary directory
  def self.tmp_file(prefix = 'tmp-', max = 1_000_000_000, dir = nil)
    dir ||= TmpFile.tmpdir
    File.expand_path(File.join(dir, random_name(prefix, max)))
  end

  def self.with_file(content = nil, erase = true, options = {})
    if content.is_a?(Hash)
      options = content
      content = nil
      erase = true
    end
    if erase.is_a?(Hash)
      options = erase
      erase = true
    end

    prefix = options[:prefix] || 'tmp-'
    tmpdir = options[:tmpdir] || TmpFile.tmpdir
    max = options[:max] || 1_000_000_000
    tmpfile = tmp_file prefix, max, tmpdir
    tmpfile += ".#{options[:extension]}" if options[:extension]

    FileUtils.mkdir_p tmpdir
    if IO === content
      File.open(tmpfile, 'wb') do |f|
        begin
          while c = content.readpartial(1024)
            f << c
          end
        rescue EOFError
        end
      end
    elsif !content.nil?
      File.open(tmpfile, 'w') { |f| f.write content }
    end

    result = yield(tmpfile)

    FileUtils.rm_rf tmpfile if File.exist?(tmpfile) && erase

    result
  end

  def self.with_dir(erase = true, options = {})
    prefix = options[:prefix] || 'tmpdir-'
    tmpdir = tmp_file prefix

    FileUtils.mkdir_p tmpdir

    result = yield(tmpdir)

    FileUtils.rm_rf tmpdir if File.exist?(tmpdir) && erase

    result
  end
end
