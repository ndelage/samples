class ArtLogParser
  # Using libxml-ruby
  require 'xml'

  attr_accessor :log_filename, :bundle, :process_set

  def initialize( filename, bundle, process_set )
    self.log_filename = filename
    self.bundle = bundle
    self.process_set = process_set
  end

  def hydrate_processing_steps
    parser = XML::Parser.file( self.log_filename )
    doc = parser.parse
    processing_steps = Array.new
    # There's a reason (supposedly) we keep the process_entries in a
    # separate variable. Not sure of the details. See here if you're curious:
    # http://libxml.rubyforge.org/rdoc/classes/LibXML/XML/Document.html#M000471
    process_entries = doc.find('//bundle_processing_log/processing_step')
    process_entries.each do |p|
      hydrate_processing_step( p )
    end

    return processing_steps
  end


  def hydrate_processing_step( processing_step_element )
    if processing_step_element
      step = ProcessingStep.create( :process_set => self.process_set,
                                    :processing_step_type => ProcessingStepType.find_or_create_by_key( processing_step_element['name'] ) )
      
      # TODO: Collect runtime on the processing_status object
      step.processing_status.client_run_time = processing_step_element['runtime']
      step.processing_status.run_status = processing_step_element['run_status']
      step.processing_status.save
      
      # Load any output files. We just concern ourselves with
      # the a single "document" preview for now.
      document_preview_element = processing_step_element.find_first( "output/preview[@type='document']" )
      if document_preview_element
        # We want to add an ArtRevision to this processing_step.
        # An ArtRevision has a preview and art_file. Both of these
        # are StoredResources. We look within our art_processing_bundle
        # to find the StoredResource whose document's original_filename
        # matches the value of our preview element

        # We don't match the extension for previews, because they've been converted from PSD to PNG, so our extensions
        # don't match up.
        preview_resource = self.bundle.preview_resource_group.find_stored_resource( document_preview_element.content, ignore_extension=true )
        if preview_resource
          preview_bounds = nil
          preview_resolution = nil
          version_key = nil
          
          if !document_preview_element['bounds'].blank?
            preview_bounds = document_preview_element['bounds'].split( "," ).map{ |b| b.to_i }
          end

          if !document_preview_element['resolution'].blank?
            preview_resolution = document_preview_element['resolution'].to_i
          end
          
          # if we don't have a version_key set in the log, art_revision will use
          # the processing_step's type.
          if !document_preview_element['version_key'].blank?
            version_key = document_preview_element['version_key']
          end

          # An art_revision might already exist for our service_list, version_key
          # and bounds, use the existing one if possible
          self.set_or_create_art_revision_for_preview( step, preview_bounds, preview_resolution, version_key, preview_resource )

        else
          raise "Couldn't find a matching preview resource!, searched for: " + document_preview_element.content + "\n"
        end
      end

      # Load any document_annotation elements
      document_annotations = processing_step_element.find( 'document_annotation')
      document_annotations.each do |a|
        annotation = hydrate_document_annotation( a )
        if annotation
          annotation.processing_step = step
          annotation.save
        end
      end

      # Load any item_annotation elements
      item_annotations = processing_step_element.find( 'item_annotation')
      item_annotations.each do |a|
        annotation = hydrate_item_annotation( a )
        if annotation
          annotation.processing_step = step
          annotation.save
        end
      end

      step.combine_textrange_annotations
      return step
    end

    return nil
  end

  def set_or_create_art_revision_for_preview( processing_step, preview_bounds, preview_resolution, version_key, preview_resource )
    service_list = processing_step.process_set.service_offering_keys

    # are we working on art_revisions for a visual_comparison? if so, our
    # art_revisions should already exist

    if self.bundle.queue_item && self.bundle.queue_item.options[:art_revision_id]
      revision = ArtRevision.find( self.bundle.queue_item.options[:art_revision_id] )
      if revision.preview.nil? &&
         revision.version_key == version_key &&
         (revision.preview_bounds.nil? || revision.preview_bounds == preview_bounds ) &&
         (revision.service_list - service_list).empty?


        if revision.preview_bounds.nil?
          revision.preview_bounds = preview_bounds
        end
        revision.preview_resolution = preview_resolution
        revision.preview = preview_resource
        revision.save
        return revision

      else
        raise "Preview attributes do not match existing art_revision"
      end
    else
      # otherwise, we create a new art_revision
      ArtRevision.create( :processing_step => processing_step,
                          :preview_bounds => preview_bounds,
                          :preview_resolution => preview_resolution,
                          :version_key => version_key,
                          :preview => preview_resource)
    end

  end

  def hydrate_active_record_attributes( active_record_obj, xml_element )
    for attribute_name in active_record_obj.attribute_names
      # We use the send method as a setter to help keep this code DRY
      if xml_element.find_first( attribute_name )
          active_record_obj.send( attribute_name + "=", CGI.unescape( xml_element.find_first( attribute_name ).content ) )
        end
    end
  end

  def hydrate_document_annotation( annotation_element )
    if annotation_element
      annotation = DocumentAnnotation.new
      annotation_type = AnnotationType.find_by_key(annotation_element['key'])
      if annotation_type.nil?
        # If we couldn't find an annotation type, create new one, setting the name to a value based on the key
        annotation_type = AnnotationType.create( :key => annotation_element['key'],
                                                 :name => annotation_element['key'].gsub( "_", " ").titleize,
                                                 :annotation_group => AnnotationGroup.find_by_name( DEFAULT_ANNOTATION_TYPE ) )
      end
      annotation.annotation_type = annotation_type

      if annotation_element.find_first( 'original_value')
        annotation.original_value = annotation_element.find_first( 'original_value').content
      end
      if annotation_element.find_first( 'original_units')
        annotation.original_units = annotation_element.find_first( 'original_units').content
      end


      if annotation_element.find_first( 'final_value')
        annotation.final_value = annotation_element.find_first( 'final_value').content
      end
      if annotation_element.find_first( 'final_units')
        annotation.final_units = annotation_element.find_first( 'final_units').content
      end

      return annotation
    end

    return nil
  end

  def hydrate_item_annotation( annotation_element )
    if annotation_element
      annotation = ItemAnnotation.new
      annotation_type = AnnotationType.find_by_key( annotation_element['key'] )
      if annotation_type.nil?
        # If we couldn't find an annotation type, create new one, setting the name to a value based on the key
        annotation_type = AnnotationType.create( :key => annotation_element['key'],
                                                 :name => annotation_element['key'].gsub( "_", " ").titleize,
                                                 :annotation_group => AnnotationGroup.find_by_name( DEFAULT_ANNOTATION_TYPE ) )
      end
      annotation.annotation_type = annotation_type

      # We should have an ROI element
      annotation.roi = hydrate_roi( annotation_element.find_first( 'roi') )

      if dimensions_element = annotation_element.find_first( 'dimensions')
        annotation.pt_width = dimensions_element.find_first( 'width').content
        annotation.pt_height = dimensions_element.find_first( 'height').content
      end

      # We might have a custom summary available
      custom_summary_element = annotation_element.find_first( 'custom_summary')
      if custom_summary_element &&
         ! custom_summary_element.content.blank?
        annotation.custom_summary = CGI.unescape( custom_summary_element.content )
      end

      # Set the page_item_id and parent_item_id if available
      if annotation_element.find_first( 'page_item_id')
        annotation.page_item_id = annotation_element.find_first( 'page_item_id').content
      end
      if annotation_element.find_first( 'parent_id')
        annotation.parent_item_id = annotation_element.find_first( 'parent_id').content
      end

      states = annotation_element.find( 'state')
      states.each do |s|
        if s['version'] == "original"
          annotation.original_state = hydrate_state( s )
        elsif s['version'] == "final"
          annotation.final_state = hydrate_state( s )
        end
      end

      return annotation
    end

    return nil
  end

  def hydrate_color( color_element )
    # Here we take a color XML element and hydrate a model object with the same attributes
    # before doing so, we take a look to see if the same color already exists. No point
    # in keeping copies of the same color hanging around. Especially when converting from
    # CMYK to RGB takes some time to lookup the RGB value in our special lookup image (see
    # the Color class)
    if valid_color_element( color_element )

      component_values = color_element.find_first( 'values' ).content
      color_type = color_element.find_first( 'color_type' ).content
      color_model_name = color_element.find_first( 'color_model' ).content
      if color_model_name
        color_model = ColorModel.find_by_name( color_model_name.downcase )
        # We must have a color_model to create a color
        unless color_model.nil?
          return Color.find_or_create_by_component_values_and_color_model_id_and_color_type( component_values, color_model.id, color_type )
        end
      end    

    else
      raise 'Invalid color XML element: #{color_element.to_s}'
    end
    
    return nil
  end

  def valid_color_element( element )
    if element &&
       element.find_first( 'values' ) &&
       element.find_first( 'color_type' ) &&
       element.find_first( 'color_model' )
      return true
    else
      return false
    end
    
  end

  def hydrate_roi( roi_element )
    if roi_element
      # For now, all we support is a rectangle type ROI
      if roi_element.find_first('rectangle')
        rect_element = roi_element.find_first('rectangle')
        rect_roi = RectangleRoi.new
        hydrate_active_record_attributes( rect_roi, rect_element )
        return rect_roi
      end
    end

    return nil
  end

  def hydrate_state( state_element )
    if state_element
      state = ItemState.new
      hydrate_active_record_attributes( state, state_element )

      if state_element.find_first( 'appearance')
        appearance_element = state_element.find_first( 'appearance' )
        appearance = Appearance.new
        state.appearance = appearance
        fill_element = appearance_element.find_first( 'fill' )
        stroke_element = appearance_element.find_first( 'stroke' )
        if fill_element
          # We conver the value 'true' to a true boolean
          appearance.fill_overprint = fill_element['overprint'].match('true') != nil if fill_element['overprint']
          # TODO: Add support for gradients as fills and strokes
          # Color elements are one type of fill. We don't support any others at this time.
          # Support for gradients will come next.
          appearance.fill = hydrate_color( fill_element.find_first( 'color' ) )
          if fill_element.find_first( 'color' ) &&
             fill_element.find_first( 'color' ).find_first('color_name' )
            appearance.fill_name = fill_element.find_first( 'color' ).find_first('color_name' ).content
          end
        end

        if stroke_element
          # We convert the value 'true' to a true boolean
          appearance.stroke_overprint = stroke_element['overprint'].match('true') != nil if stroke_element['overprint']
          appearance.stroke_width = stroke_element['stroke_width'] if stroke_element['stroke_width']
          appearance.stroke = hydrate_color( stroke_element.find_first( 'color' ) )
          if stroke_element.find_first( 'color' ) &&
             stroke_element.find_first( 'color' ).find_first('color_name' )
            appearance.stroke_name = stroke_element.find_first( 'color' ).find_first('color_name' ).content
          end
        end
      end

      return state
    end

    return nil
  end

end