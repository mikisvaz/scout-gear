require_relative 'misc'
require_relative 'log'
require 'fileutils'

module TmpFile
  MAX_FILE_LENGTH = 150

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

  def self.in_dir(*args)
    with_dir(*args) do |dir|
      Misc.in_dir dir do
        yield dir
      end
    end
  end

  def self.tmp_for_file(file, tmp_options = {}, other_options = {})
    persistence_file = IndiferentHash.process_options tmp_options, :file
    return persistence_file unless persistence_file.nil?

    prefix = IndiferentHash.process_options tmp_options, :prefix

    if prefix.nil?
      perfile = file.to_s.gsub(/\//, '>') 
    else
      perfile = prefix.to_s + ":" + file.to_s.gsub(/\//, '>') 
    end

    perfile.sub!(/\.b?gz$/,'')

    if other_options.include? :filters
      other_options[:filters].each do |match,value|
        perfile = perfile + "&F[#{match}=#{Misc.digest(value)}]"
      end
    end

    persistence_dir = IndiferentHash.process_options(tmp_options, :dir) || Persist.cachedir 
    Path.setup(persistence_dir) unless Path === persistence_dir

    filename = perfile.gsub(/\s/,'_').gsub(/\//,'>')
    clean_options = other_options.dup
    clean_options.delete :unnamed
    clean_options.delete "unnamed"

    filename = filename[0..MAX_FILE_LENGTH] << Misc.digest(filename[MAX_FILE_LENGTH+1..-1]) if filename.length > MAX_FILE_LENGTH + 10

    options_md5 = Misc.digest(clean_options)
    filename  << ":" << options_md5 unless options_md5.empty?

    persistence_dir[filename]
  end
end
