# encoding: utf-8
# Add a callback - to be executed before each request in development,
# and at startup in production - to patch existing app classes.
# Doing so in init/environment.rb wouldn't work in development, since
# classes are reloaded, but initialization is not run each time.
# See http://stackoverflow.com/questions/7072758/plugin-not-reloading-in-development-mode
#
Rails.configuration.to_prepare do

   OutgoingMessage.class_eval do
      
      def default_letter
            return nil if self.message_type == 'followup'
            "На підставі статей 1, 13, 19, 20 Закону України «Про доступ до публічної інформації» від 13 січня 2011 року, які надають право звертатись із запитами до розпорядників інформації щодо надання публічної інформації, прошу надати наступну інформацію (наступні документи):\n\n\n"    
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
        #if !self.body.include?(self.info_request.user.name)
         #   errors.add(:body, _("Будь ласка, підпишіться іменем, вказаним при реєстрації - #{self.info_request.user.name}"))
        #end
        #if !MySociety::Validate.uses_mixed_capitals(self.body)
         #   errors.add(:body, _('Please write your message using a mixture of capital and lower case letters. This makes it easier for others to read.'))
        #end
        #if self.what_doing.nil? || !['new_information', 'internal_review', 'normal_sort'].include?(self.what_doing)
         #   errors.add(:what_doing_dummy, _('Please choose what sort of reply you are making.'))
        #end
      end
    end    
    
    User.class_eval do
    
      def lawyer? 
        admin_level == 'lawyer'
      end
  
      def legal_comment? 
        (lawyer?) || (has_role? :admin)
      end
    end
    
    InfoRequest.class_eval do
    
      def self.matching_incoming_email(emails)
        requests = Array(emails).map { |email| find_by_incoming_email(email) }.compact
        if requests.size == 0
          guesses = guess_by_incoming_email(emails)
          if guesses.size == 1
            requests = [guesses.first[:info_request]]
          end
        end
        requests
      end
    
      def self._extract_id_hash_from_email(incoming_email)
        # Match case insensitively, FOI officers often write Request with capital R.
        incoming_email = incoming_email.downcase

        # The optional bounce- dates from when we used to have separate emails for the envelope from.
        # (that was abandoned because councils would send hand written responses to them, not just
        # bounce messages)
        incoming_email =~ /r[a-z]+-(?:bounce-)?([a-z0-9]+)-([a-z0-9]+)/

        id = _id_string_to_i($1)
        hash = _clean_idhash($2)

        [id, hash]
      end
    
      def self._guess_idhash_from_email(incoming_email)
        incoming_email = incoming_email.downcase
        incoming_email =~ /r[a-z]+\-?(\w+)-?(\w{8})@/

        id = _id_string_to_i(_clean_idhash($1))
        id_hash = $2

        if id_hash.nil? && incoming_email.include?('@')
          # try to grab the last 8 chars of the local part of the address instead
          local_part = incoming_email[0..incoming_email.index('@')-1]
          id_hash =
            if local_part.length >= 8
              _clean_idhash(local_part[-8..-1])
            end
        end

        [id, id_hash]
      end
    end
    
    IncomingMessage.class_eval do
    
      def get_body_for_html_display(collapse_quoted_sections = true)
        text = get_main_body_text_unfolded
        folded_quoted_text = get_main_body_text_folded

        if collapse_quoted_sections
          text = folded_quoted_text
        end
        text = MySociety::Format.simplify_angle_bracketed_urls(text)
        text = CGI.escapeHTML(text)
        text = MySociety::Format.make_clickable(text, :contract => 1)


        email_pattern = Regexp.escape(_("email address"))
        mobile_pattern = Regexp.escape(_("mobile number"))
        text.gsub!(/\[(#{email_pattern}|#{mobile_pattern})\]/,
                   '[<a href="/help/officers#mobiles">\1</a>]')

        if collapse_quoted_sections
          text = text.gsub(/(\s*FOLDED_QUOTED_SECTION\s*)+/m, "FOLDED_QUOTED_SECTION")
          text.strip!
          if text == "FOLDED_QUOTED_SECTION"
            text = "[Subject only] " + CGI.escapeHTML(self.subject || '') + text
          end
          text = text.gsub(/FOLDED_QUOTED_SECTION/, "\n\n" + '<span class="unfold_link"><a href="?unfold=1#incoming-'+self.id.to_s+'">'+_("показати цитоване")+'</a></span>' + "\n\n")
        else
          if folded_quoted_text.include?('FOLDED_QUOTED_SECTION')
            text = text + "\n\n" + '<span class="unfold_link"><a href="?#incoming-'+self.id.to_s+'">'+_("сховати цитоване")+'</a></span>'
          end
        end
        text.strip!

        text = ActionController::Base.helpers.simple_format(text)
        if text.match(/This message was created automatically by mail delivery software/)
          if text.match(/No action is required on your part. Delivery attempts will continue/)
            text = "<p class='delivery-error'>Не вдалося доставити листа розпоряднику. Ми спробуємо ще раз, поки що нічого не потрібно робити</p>"
          elsif text.match(/This is a permanent error/)
            text = "<p class='delivery-error'>Не вдалося доставити листа розпоряднику. Можливо, ця адреса вже недійсна, в розпорядника переповнена пошта або вони відмовляються отримувати листи з Доступа. Ви можете спробувати написати їм з власної пошти</p>"
          end
        end
        text.html_safe
      end

    end
    
end
