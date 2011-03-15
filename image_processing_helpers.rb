class ImageProcessingHelpers
  require 'RMagick'
  
  # Options passed must include the final width and height
  def self.expand_canvas( source_filename, options )
    options.reverse_merge!( :bg_color => "rgba(255,255,255)",
                            :gravity => Magick::NorthWestGravity, 
                            :composition_method => Magick::AtopCompositeOp,
                            :x_offset => 0,
                            :y_offset => 0 )

    original_image = Magick::Image::read( source_filename ).first

    if options[:pattern]
      new_canvas = Magick::Image::read( "pattern:#{options[:pattern]}" ) {
        self.size = "#{options[:width]}x#{options[:height]}"
      }.first
    else
      new_canvas = Magick::Image.new( options[:width], options[:height] ) {
        self.background_color = options[:bg_color]
      }
    end
    
    new_canvas.composite!(original_image, options[:gravity], options[:x_offset], options[:y_offset], options[:composition_method] )
    
    # Destroy our original to release the memory used
    original_image.destroy!
    
    # Write out the canvas, overwriting the original image
    new_canvas.write( source_filename ) {self.depth = 8}
    
    # Destroy our canvas to release the memory used
    new_canvas.destroy!  
  end

  def self.match_canvas_sizes( previews )
    max_dimensions = ImageProcessingHelpers.max_dimensions( previews )

    # Loop again to resize the smaller previews
    if max_dimensions[:height] > 0 && max_dimensions[:width] > 0
      for preview in previews
        if preview.height != max_dimensions[:height] ||
           preview.width != max_dimensions[:width]

          GC.start
          # Write our preview to a tmp file
          preview_filename = preview.to_tmp_file
          # Handle any errors
          unless preview_filename
            raise "Error loading process_set. Tmp file preview_filename was nil when expanding: " +
                    preview.document_uploaded_file_name
          end
          
          unless File.exist? preview_filename
            raise "Preview file doesn't exist: " + preview_filename
          end
          

          # Then use the image processing helper to resize the preview
          # TODO: Determine who will catch any possible errors, for now they float up
          ImageProcessingHelpers.expand_canvas( preview_filename, max_dimensions )
          # Our preview file should be updated, so we re-save the preview StoredResource
          preview.document = File.new( preview_filename )
          preview.save!

          FileUtils.rm( preview_filename ) if File.exist? preview_filename
        end
      end
    end
  end

  def self.max_dimensions( previews )
	{ :height => preview.collect{ |p| p.height }.max, 
	  :width => preview.collect{ |p| p.width }.max }
  end
  
end