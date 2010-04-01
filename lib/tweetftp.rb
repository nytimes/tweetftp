require 'rubygems'
require 'base64'
require 'digest/md5'
require 'twitter'
require 'tempfile'

TWEETFTP_HASHTAG = "#tweetftp"

class Tweetftp
  def initialize(username, password)
    auth = Twitter::HTTPAuth.new(username, password)
    @twitter = Twitter::Base.new(auth)
  end
  
  ##
  # Uploads a file with tweetftp
  #
  # @par
  def upload(file, options={})
    options[:name] ||= file.gsub(/.+\//, '')
    
    encoded = `uuencode -m #{file} #{options[:name]}`
    raise "Error encoding file #{file}" unless $? == 0

    options[:hash] = Base64.encode64(Digest::MD5.digest(encoded)).gsub(/=+$/, '').gsub('+', '-').gsub('/', '_').rstrip
    count = 0
    
    encoded.each do |line|
      line = line.rstrip
      break if line =~ /^===/
      if count == 0
        # info line
        upload_header_line(line, options)
        upload_description(options)
      else
        upload_data_line(line, count - 1, options)
      end
      
      count += 1
    end
    
    upload_end_line(count - 1, options)
  end
  
  # For the MD5 hash, search for all tweets matching; download, sort by count at beginning
  def download(hash, sender, options={})
    options[:save_to] ||= '/'
    page = 1
    
    fragments = []
    
    # hard limit from twitter
    while page <= 100
      search = Twitter::Search.new(hash).from(sender.gsub(/^@/, '')).page(page)
      search = search.to(options[:to].gsub(/^@/, '')) if options[:to]
      
      count = 0
      
      search.each do |result|
        count += 1
        fragments << result[:text].gsub(/^@[\w_]+\s/, '')
      end
      
      break if count == 0 || fragments.any? {|f| f =~ /^==BEGIN/ }
    end
    
    # we have all the fragments
    tf = Tempfile.new 'tweetftp'

    sorted_fragments = fragments.reject {|f| f =~ /^==/}.sort_by {|a| a.to_i }
    
    #puts fragments.inspect

    header = fragments.detect {|f| f =~ /^==BEGIN/}
    
    raise "No header found!" if header.nil?
    
    if header =~ /^==BEGIN ([^\s]+) (\d+) /
      filename = $1
      mode = $2
    else
      raise "Unable to parse the header"
    end

    tf.write "begin-base64 #{mode} tweetftp.tmp\n"
    
    sorted_fragments.each do |f|
      if f =~ /(\d+) ([a-zA-Z0-9\+\=]+) ([a-zA-Z0-9\-\_]+) #tweetftp/
        tf.write $2+"\n"
      end
    end
    
    tf.write "====\n"
    tf.close
    
    final_path = "#{options[:save_to].gsub(/\/$/, '')}/#{filename}"

    system("uudecode -o #{final_path} #{tf.path}")
    final_path
  end
  
private
  def upload_tweet(line, options)
    status = options.key?(:to) ? "#{options[:to]} " : ''
    status << line
  
    #puts status
    @twitter.update(status)
  end

  def upload_header_line(line, options)
    if line =~ /^begin-base64\s(\d+)\s/
      mode = $1
    else
      mode = 600
    end
    
    upload_tweet("==BEGIN #{options[:name]} #{mode} #{options[:hash]} #{TWEETFTP_HASHTAG}", options)
  end
  
  def upload_description(options)
    txt = ''
    txt += options[:description]
    txt += ' '
    
    if options[:keywords]
      txt += options[:keywords].map {|k| "##{k.gsub(/^#/, '')}"}.join(' ')
    end
    
    txt.strip!
    return if txt.empty?
    
    txt.gsub(/(.{1,77})( +|$\n?)|(.{1,77})/, "\\1\\3\n").lines.each_with_index do |l,i|
      upload_tweet("==DESC #{i} #{l.chomp} #{options[:hash]} #{TWEETFTP_HASHTAG}", options)
    end
  end
  
  def upload_data_line(line, count, options)
    upload_tweet("#{count} #{line} #{options[:hash]} #{TWEETFTP_HASHTAG}", options)
  end
  
  def upload_end_line(count, options)
    upload_tweet("==END #{options[:name]} #{count} #{options[:hash]} #{TWEETFTP_HASHTAG}", options)
  end
end
