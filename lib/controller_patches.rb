# encoding: utf-8
# Add a callback - to be executed before each request in development,
# and at startup in production - to patch existing app classes.
# Doing so in init/environment.rb wouldn't work in development, since
# classes are reloaded, but initialization is not run each time.
# See http://stackoverflow.com/questions/7072758/plugin-not-reloading-in-development-mode
#
require 'dispatcher'
Dispatcher.to_prepare do

  RequestController.class_eval do
     def new
     
        if Configuration::force_registration_on_new_request && !authenticated?(
                :web => _("To send your FOI request"),
                :email => _("Then you'll be allowed to send FOI requests."),
                :email_subject => _("Confirm your email address")
            )
            # do nothing - as "authenticated?" has done the redirect to signin page for us
            return
        end
        # All new requests are of normal_sort
        if !params[:outgoing_message].nil?
            params[:outgoing_message][:what_doing] = 'normal_sort'
        end

        # If we've just got here (so no writing to lose), and we're already
        # logged in, force the user to describe any undescribed requests. Allow
        # margin of 1 undescribed so it isn't too annoying - the function
        # get_undescribed_requests also allows one day since the response
        # arrived.
        if !@user.nil? && params[:submitted_new_request].nil? && !@user.can_leave_requests_undescribed?
            @undescribed_requests = @user.get_undescribed_requests
            if @undescribed_requests.size > 1
                render :action => 'new_please_describe'
                return
            end
        end

        # Banned from making new requests?
        user_exceeded_limit = false
        if !authenticated_user.nil? && !authenticated_user.can_file_requests?
            # If the reason the user cannot make new requests is that they are
            # rate-limited, it’s possible they composed a request before they
            # logged in and we want to include the text of the request so they
            # can squirrel it away for tomorrow, so we detect this later after
            # we have constructed the InfoRequest.
            user_exceeded_limit = authenticated_user.exceeded_limit?
            if !user_exceeded_limit
                @details = authenticated_user.can_fail_html
                render :template => 'user/banned'
                return
            end
            # User did exceed limit
            @next_request_permitted_at = authenticated_user.next_request_permitted_at
        end

        # First time we get to the page, just display it
        if params[:submitted_new_request].nil? || params[:reedit]
            if user_exceeded_limit
                render :template => 'user/rate_limited'
                return
            end

            params[:info_request] = { } if !params[:info_request]

            # Read parameters in - first the public body (by URL name or id)
            if params[:url_name]
                if params[:url_name].match(/^[0-9]+$/)
                    params[:info_request][:public_body_id] = params[:url_name]
                else
                    public_body = PublicBody.find_by_url_name_with_historic(params[:url_name])
                    raise ActiveRecord::RecordNotFound.new("None found") if public_body.nil? # XXX proper 404
                    params[:info_request][:public_body_id] = public_body.id
                end
            elsif params[:public_body_id]
                params[:info_request][:public_body_id] = params[:public_body_id]
            end
            if !params[:info_request][:public_body_id]
                # compulsory to have a body by here, or go to front page which is start of process
                redirect_to frontpage_url
                return
            end

            # ... next any tags or other things
            params[:info_request][:title] = params[:title] if params[:title]
            params[:info_request][:tag_string] = params[:tags] if params[:tags]

            @info_request = InfoRequest.new(params[:info_request])
            params[:info_request_id] = @info_request.id
            params[:outgoing_message] = {} if !params[:outgoing_message]
            params[:outgoing_message][:body] = params[:body] if params[:body]
            params[:outgoing_message][:default_letter] = params[:default_letter] if params[:default_letter]
            params[:outgoing_message][:info_request] = @info_request              
            
            @outgoing_message = OutgoingMessage.new(params[:outgoing_message])
            @outgoing_message.set_signature_name(@user.name) if !@user.nil?
           
	        if @info_request.public_body.is_requestable?
                render :action => 'new'
            else
                if @info_request.public_body.not_requestable_reason == 'bad_contact'
                    render :action => 'new_bad_contact'
                else
                    # if not requestable because defunct or not_apply, redirect to main page
                    # (which doesn't link to the /new/ URL)
                    redirect_to public_body_url(@info_request.public_body)
                end
            end
            return
        end

        # See if the exact same request has already been submitted
        # XXX this check should theoretically be a validation rule in the
        # model, except we really want to pass @existing_request to the view so
        # it can link to it.
        @existing_request = InfoRequest.find_by_existing_request(params[:info_request][:title], params[:info_request][:public_body_id], params[:outgoing_message][:body])

        # Create both FOI request and the first request message
        @info_request = InfoRequest.new(params[:info_request])
        @outgoing_message = OutgoingMessage.new(params[:outgoing_message].merge({
            :status => 'ready',
            :message_type => 'initial_request'
        }))
        @info_request.outgoing_messages << @outgoing_message
        @outgoing_message.info_request = @info_request

        # Maybe we lost the address while they're writing it
        if !@info_request.public_body.is_requestable?
            render :action => 'new_' + @info_request.public_body.not_requestable_reason
            return
        end

        # See if values were valid or not
        if !@existing_request.nil? || !@info_request.valid?
            # We don't want the error "Outgoing messages is invalid", as in this
            # case the list of errors will also contain a more specific error
            # describing the reason it is invalid.
            @info_request.errors.delete("outgoing_messages")

            render :action => 'new'
            return
        end

        # Show preview page, if it is a preview
        if params[:preview].to_i == 1
            message = ""
            if @outgoing_message.contains_email?
                if @user.nil?
                    message += (_("<p>You do not need to include your email in the request in order to get a reply, as we will ask for it on the next screen (<a href=\"%s\">details</a>).</p>") % [help_privacy_path+"#email_address"]).html_safe;
                else
                    message += (_("<p>You do not need to include your email in the request in order to get a reply (<a href=\"%s\">details</a>).</p>") % [help_privacy_path+"#email_address"]).html_safe;
                end
                message += _("<p>We recommend that you edit your request and remove the email address.
                If you leave it, the email address will be sent to the authority, but will not be displayed on the site.</p>")
            end
            if @outgoing_message.contains_postcode?
                message += _("<p>Your request contains a <strong>postcode</strong>. Unless it directly relates to the subject of your request, please remove any address as it will <strong>appear publicly on the Internet</strong>.</p>");
            end
            if not message.empty?
                flash.now[:error] = message.html_safe
            end
            
            render :action => 'preview'
            return
        end

        if user_exceeded_limit
            render :template => 'user/rate_limited'
            return
        end

        if !authenticated?(
                :web => _("To send your FOI request"),
                :email => _("Then your FOI request to {{public_body_name}} will be sent.",:public_body_name=>@info_request.public_body.name),
                :email_subject => _("Confirm your FOI request to ") + @info_request.public_body.name
            )
            # do nothing - as "authenticated?" has done the redirect to signin page for us
            return
        end

        if params[:post_redirect_user]
            # If an admin has clicked the confirmation link on a users behalf,
            # we don’t want to reassign the request to the administrator.
            @info_request.user = params[:post_redirect_user]
        else
            @info_request.user = authenticated_user
        end
        # This automatically saves dependent objects, such as @outgoing_message, in the same transaction
        @info_request.save!
        # XXX send_message needs the database id, so we send after saving, which isn't ideal if the request broke here.
        @outgoing_message.send_message
        flash[:notice] = _("<p>Your {{law_used_full}} request has been <strong>sent on its way</strong>!</p>
            <p><strong>We will email you</strong> when there is a response, or after {{late_number_of_days}} working days if the authority still hasn't
            replied by then.</p>
            <p>If you write about this request (for example in a forum or a blog) please link to this page, and add an
            annotation below telling people about your writing.</p>",:law_used_full=>@info_request.law_used_full,
            :late_number_of_days => Configuration::reply_late_after_days)
        redirect_to show_new_request_url(:url_title => @info_request.url_title)
    end
  end
    
    UserController.class_eval do
        def signup
          work_out_post_redirect
          # Make the user and try to save it
          @user_signup = User.new(params[:user_signup])
          error = false
          if params[:name_public_ok] != "1"
	      flash.now[:error] = _("Ви маєте погодитись на використання вашої персональної інформації. Поставте, будь ласка, відповідну галочку.")
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
end

