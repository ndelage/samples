class ResourceServerHelper

  SIGNATURE_KEY_NAME = 'signature'
  STORE_KEY_NAME = 'store'
  MODIFIED_KEY_NAME = 'mod'
  
  # combined with 'distributed' session key to form key for digest generation
  SIGNATURE_SALT = 'e5423ad75850193a70116ba7573db3ff6e109ce7'
  DIGEST = 'SHA1'

  # should normally come from environment
  DEFAULT_RESOURCE_SERVER_OPTIONS = {
    :host => "resources.grafixmd.com",
    :port => "80",
    :protocol => "http"
    }

  def self.use_resource_server_url?(attachment, options = DEFAULT_RESOURCE_SERVER_OPTIONS)
    # Switch to return false to disable all proxy usage
    # return false

    # Only use proxy for S3 stored resources
    return attachment && attachment.options[:storage] == :s3
  end

  # visible urls will be session limited by resource server
  # so do not attempt persisting or reusing these urls outside current session
  
  # to work successfully with squid proxy acl, key needs to match
  # currently needs to be session's session_id
  
  def self.attachment_visible_url(attachment, key, style, options = DEFAULT_RESOURCE_SERVER_OPTIONS)
    if attachment
      if ResourceServerHelper.use_resource_server_url?(attachment, options)
        return ResourceServerHelper.generate_visible_url(
                key, attachment.path(style),  attachment.bucket_name, attachment.updated_at, options)
      else
        return attachment.url(style)
      end
    end

    return nil
  end

  # This generates a hash of parameters that can be used in the future to build a
  # visible url (with a future session_id)
  def self.generate_attachment_visible_url_params(attachment, style, options = DEFAULT_RESOURCE_SERVER_OPTIONS)
    if attachment
      if ResourceServerHelper.use_resource_server_url?(attachment, options)
        return {'path' => attachment.path(style),
                'store' => attachment.bucket_name,
                'updated_at' => attachment.updated_at}
      else
        return {'url' => attachment.url(style)}
      end
    end

    return nil
  end

  def self.generate_visible_url(key, path, store, updated_at, options = DEFAULT_RESOURCE_SERVER_OPTIONS)
    if key && path && store
      # signatured path must include leading slash if missing
      use_path = path
      use_path = "/#{use_path}" unless use_path[0,1] == "/"
      signature = ResourceServerHelper.generate_signature(key, use_path)
      url = "#{options[:protocol]}://#{options[:host]}:#{options[:port]}" +
           "#{use_path}?#{SIGNATURE_KEY_NAME}=#{signature}&#{STORE_KEY_NAME}=#{store}"
      url = "#{url}&#{MODIFIED_KEY_NAME}=#{updated_at}" if updated_at
      return url
    else
      return nil
    end  
  end

  def self.generate_signature(key, data)
    require 'openssl' unless defined?(OpenSSL)
    OpenSSL::HMAC.hexdigest(OpenSSL::Digest::Digest.new(DIGEST), "#{key}-#{SIGNATURE_SALT}", data)
  end

end
