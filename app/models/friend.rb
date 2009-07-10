# == Schema Information
# Schema version: 2
#
# Table name: friends
#
#  id         :integer(11)   not null, primary key
#  inviter_id :integer(11)   
#  invited_id :integer(11)   
#  status     :integer(11)   default(0)
#  created_at :datetime      
#  updated_at :datetime      
#

class Friend < ActiveRecord::Base
  
  belongs_to :inviter, :class_name => 'Profile'
  belongs_to :invited, :class_name => 'Profile'
  
  after_create :create_feed_item
  after_update :create_feed_item
  
  # Statuses Array
  
  ACCEPTED = 1
  PENDING = 0
  
  def create_feed_item
    unless(status == ACCEPTED)
      feed_item = FeedItem.create(:item => self)
      inviter.feed_items << feed_item  
      invited.feed_items << feed_item  
    end
  end
    
  def validate
    errors.add('inviter', 'inviter and invited can not be the same user') if invited == inviter
  end
  
  def description user, target = nil
    return 'friend' if status == ACCEPTED
    return 'follower' if user == inviter
    'fan'
  end
  
  def after_create
    ArNotifier.deliver_follow inviter, invited, description(inviter) if invited.wants_follow_email_notification?
    Profile.admins.first.sent_messages.create( :subject => "[#{SITE_NAME} Notice] #{inviter.full_name} is now following you", 
                                        :body => description(inviter), 
                                        :receiver => invited, :system_message => true ) if invited.wants_follow_message_notification?
  end
  
  
  class << self

    def add_follower(inviter, invited)
      a = Friend.create(:inviter => inviter, :invited => invited, :status => PENDING)
      #      logger.debug a.errors.inspect.blue
      !a.new_record?
    end
  
    
    def make_friends(user, target)
      transaction do
        if user.followed_by? target
          Friend.find(:first, :conditions => {:inviter_id => target.id, :invited_id => user.id, :status => PENDING}).update_attribute(:status, ACCEPTED)
          Friend.create!(:inviter_id => user.id, :invited_id => target.id, :status => ACCEPTED)
        else
          return add_follower(user, target)unless user.following? target
        end
      end
      true
    end
    
  
    def stop_being_friends(user, target)
      transaction do
        begin
          Friend.find(:first, :conditions => {:inviter_id => target.id, :invited_id => user.id, :status => ACCEPTED}).update_attribute(:status, PENDING)
          f = Friend.find(:first, :conditions => {:inviter_id => user.id, :invited_id => target.id, :status => ACCEPTED}).destroy
        rescue Exception
          return false
        end
      end
      true
    end
    
    
    def reset(user, target)
      #don't need a transaction here. if either fail, that's ok
      begin
        if Friend.find(:first, :conditions => {:inviter_id => target.id, :invited_id => user.id})
          Friend.find(:first, :conditions => {:inviter_id => target.id, :invited_id => user.id}).destroy # when a user is delete the remove a follwer
        end
        Friend.find(:first, :conditions => {:inviter_id => user.id, :invited_id => target.id}).destroy
        #Friend.find(:first, :conditions => {:inviter_id => target.id, :invited_id => user.id, :status => ACCEPTED}).update_attribute(:status, PENDING)
        Friend.find(:first, :conditions => {:inviter_id => target.id, :invited_id => user.id, :status => ACCEPTED}).destroy # We Need to destroy whole relationship if he remove a freind
      rescue Exception
        return true # we need something here for test coverage
      end
      true
    end
  
  
  end
  
end