require 'dispatcher'
Dispatcher.to_prepare do
    
    UserController.class_eval do
        def signup
          work_out_post_redirect
          # Make the user and try to save it
          @user_signup = User.new(params[:user_signup])
          error = false
          if params[:name_public_ok] != "1"
	      flash.now[:error] = _("Ви повинні погодитись на опублікування ваших персональних даних. Поставте, будь ласка, відповідну галочку")
	      error = true
          elsif @request_from_foreign_country && !verify_recaptcha
              flash.now[:error] = _("There was an error with the words you entered, please try again.")
              error = true
          end
          if error || !@user_signup.valid?
              # Show the form
              render :action => 'sign'
          else
              user_alreadyexists = User.find_user_by_email(params[:user_signup][:email])
              if user_alreadyexists
                  already_registered_mail user_alreadyexists
                  return
              else
                  # New unconfirmed user
                  @user_signup.email_confirmed = false
                  @user_signup.save!
                  send_confirmation_mail @user_signup
                  return
              end
          end
      end
    end
    PublicBodyController.class_eval do
      def list
        long_cache
        # XXX move some of these tag SQL queries into has_tag_string.rb
        @query = "%#{params[:public_body_query].nil? ? "" : params[:public_body_query]}%"
        @tag = params[:tag]
        @locale = self.locale_from_params()
        default_locale = I18n.default_locale.to_s
        locale_condition = "(upper(public_body_translations.name) LIKE upper(?)
                            OR upper(public_body_translations.notes) LIKE upper (?))
                            AND public_body_translations.locale = ?
                            AND public_bodies.id <> #{PublicBody.internal_admin_body.id}"
        if @tag.nil? or @tag == "all"
            @tag = "all"
            conditions = [locale_condition, @query, @query, default_locale]
        elsif @tag == 'other'
            category_list = PublicBodyCategories::get().tags().map{|c| "'"+c+"'"}.join(",")
            conditions = [locale_condition + ' AND (select count(*) from has_tag_string_tags where has_tag_string_tags.model_id = public_bodies.id
                and has_tag_string_tags.model = \'PublicBody\'
                and has_tag_string_tags.name in (' + category_list + ')) = 0', @query, @query, default_locale]
        elsif @tag.size == 2
            @tag.upcase!
            conditions = [locale_condition + ' AND public_body_translations.first_letter = ?', @query, @query, default_locale, @tag]
        elsif @tag.include?(":")
            name, value = HasTagString::HasTagStringTag.split_tag_into_name_value(@tag)
            conditions = [locale_condition + ' AND (select count(*) from has_tag_string_tags where has_tag_string_tags.model_id = public_bodies.id
                and has_tag_string_tags.model = \'PublicBody\'
                and has_tag_string_tags.name = ? and has_tag_string_tags.value = ?) > 0', @query, @query, default_locale, name, value]
        else
            conditions = [locale_condition + ' AND (select count(*) from has_tag_string_tags where has_tag_string_tags.model_id = public_bodies.id
                and has_tag_string_tags.model = \'PublicBody\'
                and has_tag_string_tags.name = ?) > 0', @query, @query, default_locale, @tag]
        end

        if @tag == "all"
            @description = ""
        elsif @tag.size == 2
            @description = _("ті, що починаються з ‘{{first_letter}}’", :first_letter=>@tag)
        else
            category_name = PublicBodyCategories::get().by_tag()[@tag]
            if category_name.nil?
                @description = _("matching the tag ‘{{tag_name}}’", :tag_name=>@tag)
            else
                @description = _(" у категорії ‘{{category_name}}’", :category_name=>category_name)
            end
        end
        PublicBody.with_locale(@locale) do
            @public_bodies = PublicBody.paginate(
              :order => "public_body_translations.name", :page => params[:page], :per_page => 100,
              :conditions => conditions,
              :joins => :translations
            )
            render :template => "public_body/list"
        end
      end
    end
    
    OutgoingMessage.class_eval do
      def default_letter
            return nil if self.message_type == 'followup'
            "На підставі статей 1, 13, 19, 20 Закону України «Про доступ до публічної інформації» від 13 січня 2011 року, які надають право звертатись із запитами до розпорядників інформації щодо надання публічноїінформації, прошу надати наступну інформацію (наступні документи):"    
        end
    end  
    
    InfoRequest.class_eval do
        validates_format_of :title, :with => /[(\320\260-\321\217)|(a-zA-Z)]/, :message => N_("Please write a summary with some text in it"), :if => Proc.new { |info_request| !info_request.title.nil? && !info_request.title.empty? }
    end
end

