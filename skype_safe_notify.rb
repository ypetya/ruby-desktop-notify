#!/usr/bin/env ruby
#
# Kiss Péter - ypetya@gmail.com
#
# This is a simple notify script for skype, ( and you can use it for other notify actions as well like termtter say plugin )
# It helps me to listen new message texts,
# and also helps to create an automatic blog via the incoming links in skype.
#
# Requirements:
#
#  * min. ubuntu 810
#  * $apt-get install espeak skype
#  * gem install nokigiri mechanize
#
# How to use this:
#
# Setup skype Notifiers in advanced view to run this script
# [absolute path]skype_safe_notify.rb %sskype %smessage
#
#
# first word identifies the other contact we are makeing an own sound from this info :)

#requirements
require 'rubygems'
require 'nokogiri'
require 'mechanize'

require 'net/http'
require 'uri'

module SkypeNotify

  # my configs
  # use this :
  load '/etc/my_ruby_scripts/settings.rb'

  DIR = ENV['HOME'] || ENV['USERPROFILE'] || ENV['HOMEPATH']

  WMII_STATUS_FILENAME = "wmii_skype_info.log"
  TMP_FILENAME = "skype_say_safe"

  # uncomment this if you do not use blogging url-s
  BLOG_NAME = 'csakacsuda'

  # do not try these urls
  NOT_VALID_URL = [ /local/, /http:\/\/[0-9\.]+[\/:]/, /private/, 
    /virgo/, /ypetya/, /admin/, /sandbox/, /szarka/, /netpincer/, 
    /blackbox/, /svn/, /authkey=\w+&/i, /iwiw/, /zoldseg/, /gtk/,
    /eleventyone/]


  EMBED_CODES= {
    :vimeo => {:get_id => /http:\/\/(www\.){0,1}vimeo\.com\/(.*)$/,
      :code =>'<object width="400" height="225"><param name="allowfullscreen" value="true" /><param name="allowscriptaccess" value="always" /><param name="movie" value="http://vimeo.com/moogaloop.swf?clip_id=EMBEDCODE&amp;server=vimeo.com&amp;show_title=1&amp;show_byline=1&amp;show_portrait=0&amp;color=&amp;fullscreen=1" /><embed src="http://vimeo.com/moogaloop.swf?clip_id=EMBEDCODE&amp;server=vimeo.com&amp;show_title=1&amp;show_byline=1&amp;show_portrait=0&amp;color=&amp;fullscreen=1" type="application/x-shockwave-flash" allowfullscreen="true" allowscriptaccess="always" width="400" height="225"></embed></object>'},
    :youtube => { :get_id => /http:\/\/(www\.){0,1}youtube\.com\/watch\?v=(.*)/,
      :code => '<object width="425" height="344"><param name="movie" value="http://www.youtube.com/v/EMBEDCODE&hl=en&fs=1"></param><param name="allowFullScreen" value="true"></param><param name="allowscriptaccess" value="always"></param><embed src="http://www.youtube.com/v/EMBEDCODE&hl=en&fs=1" type="application/x-shockwave-flash" allowscriptaccess="always" allowfullscreen="true" width="425" height="344"></embed></object>'},
    :soundcloud => {:get_id => /http:\/\/(www\.){0,1}soundcloud\.com\/(.*)$/,
      :code => '<object height="81" width="100%"> <param name="movie" value="http://player.soundcloud.com/player.swf?url=http%3A%2F%2Fsoundcloud.com%2FEMBEDCODE"></param> <param name="allowscriptaccess" value="always"></param> <embed allowscriptaccess="always" height="81" src="http://player.soundcloud.com/player.swf?url=http%3A%2F%2Fsoundcloud.com%2FEMBEDCODE" type="application/x-shockwave-flash" width="100%"></embed> </object><span>http://soundcloud.com/EMBEDCODE</span>' },
  }

  class Runner

    THINGS_TO_DO = [:create_status_file_for_wmii, # => save the first 40 chars of message
                    :generate_voice,
                    :join_args_to_message, # => create
										:get_links_to_blog, # => collect links, and replace url-s in message text for better audio experience unless defined? BLOG_NAME
										:generate_tmp_file_name, # => to avoid script injection
                    :save_message_to_file,
                    :call_speak_command,
                    :put_links_to_blog, # => unless defined? BLOG_NAME
                    :remove_tmp_file
                   ]

    def initialize
      @options = { }
    end

    def run options = { }
      @options.merge! options
      THINGS_TO_DO.each{ |thing| send( thing ) }
    end

    def create_status_file_for_wmii
      my_args = ARGV.dup
      msg = "#{my_args.shift} \"" + my_args.join(' ').gsub(/"/){'\"'}
      msg = msg.length > 40 ? msg[0..40] + '...' : msg
      msg += '"'
      @short_mess = msg
      @short_status = File.join(DIR,WMII_STATUS_FILENAME)
      File.open(@short_status,'w') do |f|
        f.puts msg
      end
    end
  
    P = (1..6).map{|x| x * 20 }
    V = ['hu+f1','hu+f2','hu+f3','hu+f4','hu+m1','hu+m2','hu+m3','hu+m4','hu+m5','hu+m6']
    S = (1..7).map{|x| 50 + x * 20 }

    def speak_command( p, v, s )
      "aoss espeak -p #{p} -v #{v} -s #{s} -a 199 -f"
    end

    def generate_voice
      return if @options[:nosound]
      uid = (@uid = ARGV.shift).sum
      @speak_command = speak_command( P[uid % P.length], V[uid % V.length], S[uid % S.length])
    end

    def generate_tmp_file_name
      @tmp_file = File.join(DIR,TMP_FILENAME)
      @copy = '1'
      while File.exists?("#{@tmp_file}.#{@copy}.txt")
        @copy.next!
      end
      @tmp_file="#{@tmp_file}.#{@copy}.txt"
    end

    def remove_tmp_file
      FileUtils.rm(@tmp_file)
    end

		def join_args_to_message
      @message= ARGV.join(' ')
		end

    def save_message_to_file
      File.open(@tmp_file,'w') do |f|
        f.puts @message
      end
    end

    def get_links_to_blog
      return unless defined? BLOG_NAME

      @new_links = []
      @new_links_html = []
      # collect links
      @message = @message.gsub(Regexp.new(URI.regexp.source.sub(/^[^:]+:/, '(http|https):'), Regexp::EXTENDED, 'n')) do
        detected_link = $&
				@new_links << detected_link.dup
				ret = ' link. '
				detected_link.gsub(/\.([^.]{3,10})$/){ ret = ($1 + ' link. ') }
				ret
      end
      # valid links: not posted yet. not in blacklist

      @new_links.each do |link|
        #check for presence
        agent, agent.user_agent_alias, agent.redirect_ok = WWW::Mechanize.new, 'Linux Mozilla', true
        oldal = agent.get( "http://#{BLOG_NAME}.freeblog.hu" )
        unless oldal.links.map{|l| l.href}.include? link
          if NOT_VALID_URL.map{|r| link =~ r}.select{|x|x}.empty?
            @new_links_html << link
          end
        end
      end
    end

    def call_speak_command
      return if @options[:nosound]
      system "notify-send #{@short_mess}" if @short_status
      system "#{@speak_command} #{@tmp_file}" if @speak_command
    end

    # push link to blog
    def put_links_to_blog
      @new_links_html ||= []      
      @new_links_html.each do |link|
        push_to_freeblog(@@settings[:freeblog].first,@@settings[:freeblog].last, simple_format(link))
        push_to_newl( link )
      end
    end

    # -- HELPERS --

    # TODO: not working, yet
    # find embed codes in foreign pages.
    def recognize_first_embed_video_code_at link
      return nil
      agent, agent.user_agent_alias, agent.redirect_ok = WWW::Mechanize.new, 'Linux Mozilla', true
      oldal = agent.get(link)
      if oldal.is_a? WWW::Mechanize::Page
        if oldal = oldal/"embed"
          return oldal.first.to_xhtml unless oldal.empty?
        end
      end
      nil
    end

    # Create blog entry html : embed code or uri
    def simple_format link
      
      link = resolve_url link

      link_as_html = %{<a href="#{link}">#{link}</a>}

      if embed_code = recognize_first_embed_video_code_at( link )
        embed_code += '<br/>'
      else
        EMBED_CODES.each do |k,v|
          link.gsub(v[:get_id]) do
            my_id = URI.encode($2.dup)
            link = v[:code].dup.gsub(/EMBEDCODE/){  my_id }
            link += '<br/>' + link_as_html
            return link
          end
        end
      #  embed_code = false
      end
      return (embed_code ? embed_code : '') + link_as_html
    end

    # blogger interface
    def push_to_freeblog( email, password, message )
      agent, agent.user_agent_alias, agent.redirect_ok = WWW::Mechanize.new, 'Linux Mozilla', true
      f = agent.get('http://freeblog.hu').forms.select {|lf| lf.action == 'fblogin.php'}.first
      @@freeblogpwd ||= password
      f.username, f.password = email,password
      f.checkboxes.first.uncheck
      m = agent.submit(f)
      m = agent.get("http://admin.freeblog.hu/edit/#{BLOG_NAME}/entries/create-entry")
      m.forms.first.fields.select{ |f| f.name =~ /CONTENT/ }.first.value = message
      agent.submit(m.forms.first)
      puts 'freeblog -> OK'
    rescue Exception => e
      puts "freeblog -> ERROR (#{e.message})"
    end

    def resolve_url(uri_str, limit = 10)
      # You should choose better exception.
      raise ArgumentError, 'HTTP redirect too deep' if limit == 0
      uri = URI.parse(uri_str)
      response = Net::HTTP.get_response( uri )
      case response
        when Net::HTTPRedirection 
          location = response['location']
          if URI.parse(location).relative?
            location = "#{uri.scheme}://#{uri.host}:#{uri.port}#{location}"
          end
          resolve_url(location, limit - 1)
        else uri_str
      end
    end

    # my special log
    def push_to_newl text
        res = Net::HTTP.post_form(URI.parse('http://91.120.21.19/update'), {
          'magick'=> "#{@uid}", 
          'text'=> text, 
          'channel' => 8})
    rescue
    end
  end


end

# you can require and disable the run
unless defined? @@SkypeNotify_NORUN

  r = SkypeNotify::Runner.new
  r.run

end
