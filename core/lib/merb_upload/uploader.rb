module Merb
  module Upload
    
    class Uploader
    
      class << self
      
        ##
        # Returns a list of processor callbacks which have been declared for this uploader
        #
        # @return [String] 
        def processors
          @processors ||= []
        end
      
        ##
        # Adds a processor callback which applies operations as a file is uploaded.
        # The argument may be the name of any method of the uploader, expressed as a symbol,
        # or a list of such methods, or a hash where the key is a method and the value is
        # an array of arguments to call the method with
        #
        # @param [*Symbol, Hash{Symbol => Array[]}] args
        # @example
        #     class MyUploader < Merb::Upload::Uploader
        #       process :sepiatone, :vignette
        #       process :scale => [200, 200]
        #     
        #       def sepiatone
        #         ...
        #       end
        #     
        #       def vignette
        #         ...
        #       end
        #     
        #       def scale(height, width)
        #         ...
        #       end
        #     end
        #
        def process(*args)
          args.each do |arg|
            if arg.is_a?(Hash)
              arg.each do |method, args|
                processors.push([method, args])
              end
            else
              processors.push([arg, []])
            end
          end
        end
        
        ##
        # Sets the storage engine to be used when storing files with this uploader.
        # Can be any class that implements a #store!(Merb::Upload::SanitizedFile) and a #retrieve!
        # method. See lib/merb_upload/storage/file.rb for an example. Storage engines should
        # be added to Merb::Plugins.config[:merb_upload][:storage_engines] so they can be referred
        # to by a symbol, which should be more convenient
        # 
        # @param [Symbol, Class] storage The storage engine to use for this uploader
        # @example
        #     storage :file
        #     storage Merb::Upload::Storage::File
        #     storage MyCustomStorageEngine
        # 
        def storage(storage = nil)
          if storage.is_a?(Symbol)
            @storage = get_storage_by_symbol(storage)
          elsif storage
            @storage = storage
          elsif @storage.nil?
            @storage = get_storage_by_symbol(Merb::Plugins.config[:merb_upload][:storage])
          end
          return @storage
        end
      
      private
      
        def get_storage_by_symbol(symbol)
          Merb::Plugins.config[:merb_upload][:storage_engines][symbol]
        end
      
      end
    
      attr_accessor :identifier
      
      attr_reader :file, :cache_id, :model, :mounted_as
      
      def initialize(model=nil, mounted_as=nil)
        @model = model
        @mounted_as = mounted_as
      end
      
      ##
      # Apply all process callbacks added through Merb::Uploader.process
      #
      def process!
        self.class.processors.each do |method, args|
          self.send(method, *args)
        end
      end
      
      ##
      # @return [String] the path where the file is currently located.
      def current_path
        file.path if file.respond_to?(:path)
      end
      
      ##
      # @return [String] the location where this file is accessible via a url
      def url
        if file.respond_to?(:url)
          file.url
        else
          '/' + current_path.relative_path_from(Merb.dir_for(:public)) if current_path
        end
      end
      
      alias_method :to_s, :url
    
      ##
      # Override this in your Uploader to change the filename.
      #
      # Be careful using record ids as filenames. If the filename is stored in the database
      # the record id will be nil when the filename is set. Don't use record ids unless you
      # understand this limitation.
      #
      # @return [String] a filename
      def filename
        identifier
      end
    
      ##
      # Override this in your Uploader to change the directory where the file backend stores files.
      #
      # Other backends may or may not use this method, depending on their specific needs.
      #
      # @return [String] a directory
      def store_dir
        Merb::Plugins.config[:merb_upload][:store_dir]
      end
    
      ##
      # Override this in your Uploader to change the directory where files are cached.
      #
      # @return [String] a directory
      def cache_dir
        Merb::Plugins.config[:merb_upload][:cache_dir]
      end
      
      ##
      # Override this in your Uploader to change the full path where the file backend stores files.
      #
      # A word of warning: don't change this unless you are doing really, really fancy stuff. In 
      # most cases, overriding store_dir is better.
      #
      # @return [String] a path
      def store_path
        store_dir / filename
      end
      
      ##
      # Override this in your Uploader to change the full path where files are cached.
      #
      # A word of warning: don't change this unless you are doing really, really fancy stuff. In 
      # most cases, overriding cache_dir is better.
      #
      # @return [String] a path
      def cache_path
        cache_dir / cache_id / filename
      end
      
      ##
      # Returns an identifier which uniquely identifies the currently cached file for later retrieval
      #
      # @return [String] a cache name, in the format YYYYMMDD-HHMM-PID-RND/filename.txt
      def cache_name
        cache_id / identifier if cache_id and identifier
      end
      
      ##
      # Caches the given file unless a file has already been cached, stored or retrieved.
      #
      # @param [File, IOString, Tempfile] new_file any kind of file object
      # @raise [Merb::Upload::FormNotMultipart] if the assigned parameter is a string
      def cache(new_file)
        cache!(new_file) unless file
      end
      
      ##
      # Caches the given file. Calls process! to trigger any process callbacks.
      #
      # @param [File, IOString, Tempfile] new_file any kind of file object
      # @raise [Merb::Upload::FormNotMultipart] if the assigned parameter is a string
      def cache!(new_file)
        @cache_id = generate_cache_id
        
        new_file = Merb::Upload::SanitizedFile.new(new_file)
        raise Merb::Upload::FormNotMultipart, "check that your upload form is multipart encoded" if new_file.string?

        @identifier = new_file.filename

        @file = new_file
        @file.move_to(cache_path)
        process!
        
        return @cache_id
      end
      
      ##
      # Retrieves the file with the given cache_name from the cache, unless a file has
      # already been cached, stored or retrieved.
      #
      # @param [String] cache_name uniquely identifies a cache file
      def retrieve_from_cache(cache_name)
        retrieve_from_cache!(cache_name) unless file
      rescue Merb::Upload::InvalidParameter
      end
      
      ##
      # Retrieves the file with the given cache_name from the cache.
      #
      # @param [String] cache_name uniquely identifies a cache file
      # @raise [Merb::Upload::InvalidParameter] if the cache_name is incorrectly formatted.
      def retrieve_from_cache!(cache_name)
        self.cache_id, self.identifier = cache_name.split('/', 2)
        @file = Merb::Upload::SanitizedFile.new(cache_path)
      end
      
      ##
      # Stores the file by passing it to this Uploader's storage engine, unless a file has
      # already been cached, stored or retrieved.
      #
      # If Merb::Plugins.config[:merb_upload][:use_cache] is true, it will first cache the file
      # and apply any process callbacks before uploading it.
      #
      # @param [File, IOString, Tempfile] new_file any kind of file object
      def store(new_file)
        store!(new_file) unless file
      end
      
      ##
      # Stores the file by passing it to this Uploader's storage engine.
      #
      # If new_file is omitted, a previously cached file will be stored.
      #
      # If Merb::Plugins.config[:merb_upload][:use_cache] is true, it will first cache the file
      # and apply any process callbacks before uploading it.
      #
      # @param [File, IOString, Tempfile] new_file any kind of file object
      def store!(new_file=nil)
        if Merb::Plugins.config[:merb_upload][:use_cache]
          cache!(new_file) if new_file
          @file = storage.store!(@file)
        else
          new_file = Merb::Upload::SanitizedFile.new(new_file)
          @identifier = new_file.filename
          @file = storage.store!(new_file)
        end
      end
      
      ##
      # Retrieves the file from the storage, unless a file has
      # already been cached, stored or retrieved.
      # 
      # @param [String] identifier uniquely identifies the file to retrieve
      def retrieve_from_store(identifier)
        retrieve_from_store!(identifier) unless file
      rescue Merb::Upload::InvalidParameter
      end
      
      ##
      # Retrieves the file from the storage.
      # 
      # @param [String] identifier uniquely identifies the file to retrieve
      def retrieve_from_store!(identifier)
        self.identifier = identifier
        @file = storage.retrieve!
      end
      
    private
    
      def storage
        @storage ||= self.class.storage.new(self)
      end

      def cache_id=(cache_id)
        raise Merb::Upload::InvalidParameter, "invalid cache id" unless valid_cache_id?(cache_id)
        @cache_id = cache_id
      end
      
      def identifier=(identifier)
        raise Merb::Upload::InvalidParameter, "invalid identifier" unless identifier =~ /^[a-z0-9\.\-\+_]+$/i
        @identifier = identifier
      end
      
      def generate_cache_id
        Time.now.strftime('%Y%m%d-%H%M') + '-' + Process.pid.to_s + '-' + ("%04d" % rand(9999))
      end
      
      def valid_cache_id?(cache_id)
        /^[\d]{8}\-[\d]{4}\-[\d]+\-[\d]{4}$/ =~ cache_id
      end
      
    end
    
  end
end