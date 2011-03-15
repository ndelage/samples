module DeleteHelper
  def self.included(base)
    base.class_eval do
      named_scope :not_deleted, :conditions => "#{self.table_name}.deleted_at IS NULL"
      named_scope :deleted, :conditions => "#{self.table_name}.deleted_at IS NOT NULL"
    end
  end

  def deleted?
    !self.deleted_at.nil?
  end
  
  def mark_deleted
    transaction do
      self.update_attribute( :deleted_at, Time.now )
      self.dependent_destroy_children.each{ |child|
        child.mark_deleted
      }
    end
  end

  def mark_not_deleted
    transaction do
      self.update_attribute( :deleted_at, nil )
      self.dependent_destroy_children.each{ |child| 
        child.mark_not_deleted
      }

      # ensure that all project_parents are marked not_deleted
      # we update the deleted_at attribute manually so we don't
      # cause all the parent's children (associations) to be
      # marked_not_deleted
      if self.respond_to? 'project_parent'
        parent = self.project_parent
        while parent
          parent.update_attribute( :deleted_at, nil )
          parent = parent.project_parent
        end
      end
    end
  end
  

  protected

  def dependent_destroy_children
    children = []
    for a in self.class.reflect_on_all_associations
        if a.options[:dependent] == :destroy
          if a.macro == :has_many
            if a.name != :children
              for child in self.send( a.name)
                if child.respond_to?( 'mark_deleted' )
                  children << child
                end
              end
            end

          else
            if obj = self.send( a.name )
              if obj.respond_to?( 'mark_deleted' )
                children << obj
              end
            end
          end

        end
      end

    children
  end

end