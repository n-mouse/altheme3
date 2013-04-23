# Add a callback - to be executed before each request in development,
# and at startup in production - to patch existing app classes.
# Doing so in init/environment.rb wouldn't work in development, since
# classes are reloaded, but initialization is not run each time.
# See http://stackoverflow.com/questions/7072758/plugin-not-reloading-in-development-mode
#
require 'dispatcher'
Dispatcher.to_prepare do

   OutgoingMessage.class_eval do
      def default_letter
            return nil if self.message_type == 'followup'
            "На підставі статей 1, 13, 19, 20 Закону України «Про доступ до публічної інформації» від 13 січня 2011 року, які надають право звертатись із запитами до розпорядників інформації щодо надання публічної інформації, прошу надати наступну інформацію (наступні документи):\n\n\n\n\n\n"    
        end
        
      def format_of_body
        if self.body.empty? || self.body =~ /\A#{get_salutation}\s+#{get_signoff}/ || self.body =~ /#{get_internal_review_insert_here_note}/
            if self.message_type == 'followup'
                if self.what_doing == 'internal_review'
                    errors.add(:body, _("Please give details explaining why you want a review"))
                else
                    errors.add(:body, _("Please enter your follow up message"))
                end
            elsif
                errors.add(:body, _("Please enter your letter requesting information"))
            else
                raise "Message id #{self.id} has type '#{self.message_type}' which validate can't handle"
            end
        end
        if !self.body.include?(self.info_request.user.name)
            errors.add(:body, _("Будь ласка, підпишіться іменем, вказаним при реєстрації - #{self.info_request.user.name}"))
        end
        if !MySociety::Validate.uses_mixed_capitals(self.body)
            errors.add(:body, _('Please write your message using a mixture of capital and lower case letters. This makes it easier for others to read.'))
        end
        if self.what_doing.nil? || !['new_information', 'internal_review', 'normal_sort'].include?(self.what_doing)
            errors.add(:what_doing_dummy, _('Please choose what sort of reply you are making.'))
        end
      end
    end    
    
        
end
