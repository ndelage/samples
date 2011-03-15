class VisualComparisonObserver < ActiveRecord::Observer

  def after_create( comparison )
    if comparison.revision_a &&
        comparison.revision_b &&
        comparison.difference_preview.nil?
      
      QueueItem.create( :queueable => comparison,
                        :process_set => nil,
                        :processing_queue => ProcessingQueue.find_by_name( 'GENERATE_VISUAL_DIFFERENCES') )
    end

  end
end