class VisualComparison < ActiveRecord::Base
  include ProcessedStateHelper
  include ServiceableHelper
  
  belongs_to :revision_a, :class_name => "ArtRevision"
  belongs_to :revision_b, :class_name => "ArtRevision"
  belongs_to :difference_preview, :class_name => "StoredResource", :dependent => :destroy
  
  has_one :queue_item, :as => :queueable, :dependent => :destroy
  has_many :service_usages, :as => :serviceable, :dependent => :destroy
  has_many :service_runs, :through => :service_usages
  has_many :process_sets, :through => :service_runs

  validates_presence_of :revision_a, :revision_b

  DIFFERENCE_HIGHLIGHT_COLOR = {:red => 255, :green => 255, :blue => 255, :opacity => 0}
  DIFFERENCE_LOWLIGHT_COLOR = {:red => 0, :green => 0, :blue => 0, :opacity => 0}

  def self.find_for_passes_and_services( pass_a, pass_b, service_key )
    return nil unless pass_a && pass_b
    
    if service_key.to_s == "validation" &&
       pass_a == pass_b
      return self.find_validation_visual_comparison( pass_a )
    elsif service_key.to_s == "pass_review"
      return self.find_pass_review_visual_comparison( pass_a, pass_b )
    end

    return nil
  end

  def self.find_pass_review_visual_comparison( pass_a, pass_b )
    pass_a_revisions = pass_a.art_revisions.for_service( :pass_review ).for_version_key( :original )
    pass_b_revisions = pass_b.art_revisions.for_service( :pass_review ).for_version_key( :original )

    matching_revisions = nil
    for r1 in pass_a_revisions
      if r2 = pass_b_revisions.detect{ |r2| r1.preview_bounds == r2.preview_bounds && 
											r1.preview_resolution == r2.preview_resolution }
        matching_revisions = [r1, r2]
      end
    end

    if matching_revisions
      return VisualComparison.find( :first, :conditions => ["revision_a_id IN (:revision_ids) AND revision_b_id IN (:revision_ids)", {:revision_ids => matching_revisions}] )
    end

    return nil
  end

  def self.find_validation_visual_comparison( pass )
    validation_art_revisions = [pass.art_revisions.for_service( :validation ).for_version_key( :original ).first,
                                pass.art_revisions.for_service( :validation ).for_version_key( :final ).first]
    validation_art_revisions.compact!
    if validation_art_revisions.size == 2
      return VisualComparison.find( :first, :conditions => ["revision_a_id IN (:revision_ids) AND revision_b_id IN (:revision_ids)", {:revision_ids => validation_art_revisions}] )
    end

    return nil
  end

  def self.create_missing_revisions_for_passes( pass_a, pass_b )
    union_bounds = VisualComparison.union_bounds_for_passes( pass_a, pass_b )

    new_revisions = []
    unless pass_a.art_revisions.for_service( :pass_review ).for_version_key( :original ).detect{ |r| r.preview_bounds == union_bounds }
      new_revisions << ArtRevision.create( :art_pass => pass_a,
                                           :service_list => ['pass_review'],
                                           :version_key => 'original',
                                           :preview_bounds => union_bounds )
    end

    unless pass_b.art_revisions.for_service( :pass_review ).for_version_key( :original ).detect{ |r| r.preview_bounds == union_bounds }
      new_revisions << ArtRevision.create( :art_pass => pass_b,
                                           :service_list => ['pass_review'],
                                           :version_key => 'original',
                                           :preview_bounds => union_bounds )
    end

    return new_revisions
  end

  def self.create_for_passes( pass_a, pass_b )
    # we create the visual_comparison and any missing art_revisions for the two
    # passes.
    union_bounds = VisualComparison.union_bounds_for_passes( pass_a, pass_b )

    revision_a = pass_a.art_revisions.for_service( :pass_review ).for_version_key( :original ).detect{ |r| r.preview_bounds == union_bounds }
    revision_b = pass_b.art_revisions.for_service( :pass_review ).for_version_key( :original ).detect{ |r| r.preview_bounds == union_bounds }

    if revision_a && revision_b
      return VisualComparison.create( :revision_a => revision_a,
                                      :revision_b => revision_b )
    else
      raise "Missing revisions for comparison between passes #{pass_a.id} and #{pass_b.id}"
    end
    
  end

  def self.union_bounds_for_passes( pass_a, pass_b )
    # we need the delivered validation art_revisions to lookup each pass'
    # preview bounds

    pass_a_validation_revision = pass_a.art_revisions.for_service( :validation ).for_version_key( :final ).first
    pass_b_validation_revision = pass_b.art_revisions.for_service( :validation ).for_version_key( :final ).first

    if pass_a_validation_revision && pass_b_validation_revision
      if pass_a_validation_revision.preview_bounds &&
         pass_b_validation_revision.preview_bounds
        # our pass_review preview bounds should be the union of the two passes, we
        # use the validation art_revisions as a source for the pass' dimensions
        return ArtRevision.ai_union_bounds( pass_a_validation_revision.preview_bounds,
                                            pass_b_validation_revision.preview_bounds )
      else
        return nil
      end
    else
      raise "Validation art_revisions weren't available for both passes, unable to calculate union bounds"
    end
  end

  def VisualComparison.missing_pass_review_comparison_pairs( art_pass )
    new_comparisons_pairs = []
    for tag in art_pass.visibility_list
      if previous_pass = art_pass.previous_pass_with_visibility_tag( tag )
        if previous_pass.processing_complete?
          # unless we already have the comparison, create a new one
          unless VisualComparison.find_pass_review_visual_comparison( art_pass, previous_pass )
            new_comparisons_pairs << [previous_pass, art_pass]
          end
        end
      end

      if next_passes = art_pass.next_passes_with_visibility_tag( tag )
        for next_pass in next_passes
          if next_pass.processing_complete?
            # unless we already have the comparison, create a new one
            unless VisualComparison.find_pass_review_visual_comparison( next_pass, art_pass )
              new_comparisons_pairs << [art_pass, next_pass]
            end
          end
        end
      end
    end

    return new_comparisons_pairs
  end

  def project_parent
    nil
  end

  def project_children( include_deleted=false )
    []
  end

  # We need to support a project association for authorization checks
  def project
    self.revision_a.art_pass.project
  end

  def art_revisions
    [self.revision_a, self.revision_b].compact
  end

  def validation?
    self.revision_a.service_list.include? 'validation'
  end

  def pass_review?
    self.revision_a.service_list.include? 'pass_review'
  end

  def type
    return 'validation'  if self.validation?
    return 'pass_review' if self.pass_review?
    
    'other'
  end

  def height( style=:original )
    self.revision_a.preview.height( style )
  end

  def width( style=:original )
    self.revision_a.preview.width( style )
  end

  def rounded_visual_change
    return nil if self.change.nil?

    rounded_value = self.change.round_to( 2 )

    # If our rounded value is 0, but the original value is greater than 0,
    # force a small non-zero value. We don't want visual change %s to just
    # 'disappear'...
	return 0.01 if rounded_value == 0.0 && self.change > 0

	return rounded_value
  end

  def queue_visual_difference_generation( process_set, originally_submitted_at=Time.now, options={} )
    QueueItem.safe_create( :queueable => self,
                           :process_set => process_set,
                           :originally_submitted_at => originally_submitted_at,
                           :processing_queue => ProcessingQueue.find_by_name( 'GENERATE_VISUAL_DIFFERENCES'),
                           :options => options )
  end

  def generate_visual_difference
    begin
      ImageProcessingHelpers.match_canvas_sizes( [self.revision_a.preview, self.revision_b.preview] )
      
      original_filename = self.revision_a.preview.to_tmp_file
      final_filename = self.revision_b.preview.to_tmp_file
      difference_filename = nil

      if original_filename && final_filename
        original_image = Magick::Image::read( original_filename ).first
        final_image = Magick::Image::read( final_filename ).first

        difference_results = VisualComparison.binary_image_compare( original_image, final_image )

        # We should have been returned two values, a difference_image (rmagick object) and the
        # visual change %
        if difference_results.length == 2
          difference_image = difference_results[0]
          change = difference_results[1]

          difference_filename = File.join( TMP_DIR, self.id.to_s + "_diff.png" )
          difference_image.write( difference_filename )
          preview_resource = StoredResource.new
          preview_resource.document = File.new( difference_filename )

          self.difference_preview = StoredResource.new( :document => File.new( difference_filename ) )
          self.change = change
          self.save

          # Make sure our rmagick memory is freed
          original_image.destroy!
          final_image.destroy!
          difference_image.destroy!
        else
          raise "Error generating difference using rmagick"
        end
      else
        raise "Unable to download both revision preview files"
      end
    ensure
      # Cleanup
      FileUtils.rm( original_filename ) if original_filename && File.exist?( original_filename )
      FileUtils.rm( final_filename ) if final_filename && File.exist?( final_filename )
      FileUtils.rm( difference_filename ) if difference_filename && File.exist?( difference_filename )
    end
  end

  def self.binary_image_compare( original_image, final_image, options = {} )
    options.reverse_merge!( :highlight_color => DIFFERENCE_HIGHLIGHT_COLOR,
                            :lowlight_color => DIFFERENCE_LOWLIGHT_COLOR,
                            :comparison_metric => Magick::MeanAbsoluteErrorMetric )
    # Here we use a quick method of image comparison. RMagick has a function compare_channel that
    # does all the work the work for us. After the comparison we can use a histogram to
    # find out how many pixels have changed.

    # The difference image should only contain two colors, the highlight and lowlight colors.
    difference_image = original_image.compare_channel( final_image, options[:comparison_metric] ) {
      self.highlight_color = Color.color_values_to_rgba_string( options[:highlight_color] )
      self.lowlight_color = Color.color_values_to_rgba_string( options[:lowlight_color] )
    }.first

    # Default to reporting no visual change
    change = 0.0

    # Since we only have two colors, our histogram hash should only have two values
    # Magick::Pixels are the keys
    histogram = difference_image.color_histogram
    for pixel in histogram.keys
      if pixel.red == options[:highlight_color][:red] &&
         pixel.green == options[:highlight_color][:green] &&
         pixel.blue == options[:highlight_color][:blue] &&
         pixel.opacity == options[:highlight_color][:opacity]

        # Change is multiplied by 100, since this is shown as a percentage in the GUI
        change = ( ( histogram[pixel].to_f / ( difference_image.columns * difference_image.rows ) ) ) * 100.0
      end
    end

    return [difference_image, change]
  end

  def display_name
    'VisualComparison'
  end

end