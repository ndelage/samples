class ArtRevision < ActiveRecord::Base
  belongs_to :art_pass
  belongs_to :preview, :class_name => 'StoredResource'
  belongs_to :art_file, :class_name => 'StoredResource'

  has_one :processing_step
  has_one :process_set, :through => :processing_step
  has_many :history_states, :dependent => :destroy
  has_many :visual_comparisons,
              :class_name => "VisualComparison",
              :finder_sql => 'SELECT * FROM visual_comparisons ' +
                             'WHERE visual_comparisons.revision_a_id = #{id} OR ' +
                             'visual_comparisons.revision_b_id = #{id}',
              :uniq => true

  serialize :preview_bounds

  acts_as_taggable_on :service

  validates_presence_of :art_pass, :version_key
  before_validation :set_art_pass_and_service_tags
  
  named_scope :for_version_key, lambda { |version_key| { :conditions => { :version_key => version_key.to_s } } }

  default_scope :order => "created_at DESC"
  
  AI_BOUNDS_LEFT = 0
  AI_BOUNDS_TOP = 1
  AI_BOUNDS_RIGHT = 2
  AI_BOUNDS_BOTTOM = 3

  def self.for_service( service_key )
    tagged_with( service_key.to_s, :on => :service )
  end

  def self.ai_union_bounds( *bounds_list )
    left_bounds = bounds_list.collect{ |b| b[AI_BOUNDS_LEFT] }
    top_bounds = bounds_list.collect{ |b| b[AI_BOUNDS_TOP] }
    right_bounds = bounds_list.collect{ |b| b[AI_BOUNDS_RIGHT] }
    bottom_bounds = bounds_list.collect{ |b| b[AI_BOUNDS_BOTTOM] }

    return [left_bounds.min,
            top_bounds.max,
            right_bounds.max,
            bottom_bounds.min]
  end

  def set_art_pass_and_service_tags
    # TODO: because of https://rails.lighthouseapp.com/projects/8994/tickets/1749-has_one-through-not-working
    # we need to access the process_set by asking the processing_step for it's process_set, not using
    # the has_one :process_set :through => :processing_step association

    if self.processing_step
      self.art_pass = self.processing_step.process_set.art_pass if self.art_pass.nil?
      self.service_list = self.processing_step.process_set.service_offering_keys if self.service_list.empty?
      self.version_key = self.processing_step.processing_step_type.key if self.version_key.nil?
    end
  end

end