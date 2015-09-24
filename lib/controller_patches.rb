# encoding: utf-8
# Add a callback - to be executed before each request in development,
# and at startup in production - to patch existing app classes.
# Doing so in init/environment.rb wouldn't work in development, since
# classes are reloaded, but initialization is not run each time.
# See http://stackoverflow.com/questions/7072758/plugin-not-reloading-in-development-mode
#
Rails.configuration.to_prepare do


  RequestController.class_eval do
      
        def describe_state
        info_request = InfoRequest.find(params[:id].to_i)
        set_last_request(info_request)

        # If this is an external request, go to the request page - we don't allow
        # state change from the front end interface.
        if info_request.is_external?
            redirect_to request_url(info_request)
            return
        end

        # Check authenticated, and parameters set.
        unless Ability::can_update_request_state?(authenticated_user, info_request)
            authenticated_as_user?(info_request.user,
                :web => _("To classify the response to this FOI request"),
                :email => _("Then you can classify the FOI response you have got from ") + info_request.public_body.name + ".",
                :email_subject => _("Classify an FOI response from ") + info_request.public_body.name)
            # do nothing - as "authenticated?" has done the redirect to signin page for us
            return
        end

        if !params[:incoming_message]
            flash[:error] = _("Please choose whether or not you got some of the information that you wanted.")
            redirect_to request_url(info_request)
            return
        end

        if params[:last_info_request_event_id].to_i != info_request.last_event_id_needing_description
            flash[:error] = _("The request has been updated since you originally loaded this page. Please check for any new incoming messages below, and try again.")
            redirect_to request_url(info_request)
            return
        end

        described_state = params[:incoming_message][:described_state]
        message = params[:incoming_message][:message]
        # For requires_admin and error_message states we ask for an extra message to send to
        # the administrators.
        # If this message hasn't been included then ask for it
        if ["error_message", "requires_admin"].include?(described_state) && message.nil?
            redirect_to describe_state_message_url(:url_title => info_request.url_title, :described_state => described_state)
            return
        end

        # Make the state change
        event = info_request.log_event("status_update",
                { :user_id => authenticated_user.id,
                  :old_described_state => info_request.described_state,
                  :described_state => described_state,
                })

        info_request.set_described_state(described_state, authenticated_user, message)

        # If you're not the *actual* requester. e.g. you are playing the
        # classification game, or you're doing this just because you are an
        # admin user (not because you also own the request).
        if !info_request.is_actual_owning_user?(authenticated_user)
            # Create a classification event for league tables
            RequestClassification.create!(:user_id => authenticated_user.id,
                                          :info_request_event_id => event.id)

            # Don't give advice on what to do next, as it isn't their request
            if session[:request_game]
                flash[:notice] = _('Thank you for updating the status of the request \'<a href="{{url}}">{{info_request_title}}</a>\'. There are some more requests below for you to classify.',:info_request_title=>CGI.escapeHTML(info_request.title), :url=>CGI.escapeHTML(request_path(info_request)))
                redirect_to categorise_play_url
            else
                flash[:notice] = _('Thank you for updating this request!')
                redirect_to request_url(info_request)
            end
            return
        end

        calculated_status = info_request.calculate_status
        # Display advice for requester on what to do next, as appropriate
        flash[:notice] = case info_request.calculate_status
        when 'waiting_response'
            _("<p>Thank you! Hopefully your wait isn't too long.</p> <p>By law, you should get a response promptly, and normally before the end of <strong>
{{date_response_required_by}}</strong>.</p>",:date_response_required_by=>view_context.simple_date(info_request.date_response_required_by))
        when 'waiting_response_overdue'
            _("<p>Thank you! Hope you don't have to wait much longer.</p> <p>By law, you should have got a response promptly, and normally before the end of <strong>{{date_response_required_by}}</strong>.</p>",:date_response_required_by=>view_context.simple_date(info_request.date_response_required_by))
        when 'waiting_response_very_overdue'
            _("<p>Thank you! Your request is long overdue, by more than {{very_late_number_of_days}} working days. Most requests should be answered within {{late_number_of_days}} working days. You might like to complain about this, see below.</p>", :very_late_number_of_days => AlaveteliConfiguration::reply_very_late_after_days, :late_number_of_days => AlaveteliConfiguration::reply_late_after_days)
        when 'not_held'
            _("<p>Thank you! Here are some ideas on what to do next:</p>
            <ul>
            <li>To send your request to another authority, first copy the text of your request below, then <a href=\"{{find_authority_url}}\">find the other authority</a>.</li>
            <li>If you would like to contest the authority's claim that they do not hold the information, here is
            <a href=\"{{complain_url}}\">how to complain</a>.
            </li>
            <li>We have <a href=\"{{other_means_url}}\">suggestions</a>
            on other means to answer your question.
            </li>
            </ul>",
            :find_authority_url => "/new",
            :complain_url => CGI.escapeHTML(unhappy_url(info_request)),
            :other_means_url => CGI.escapeHTML(unhappy_url(info_request)) + "#other_means")
        when 'rejected'
            _("Oh no! Sorry to hear that your request was refused. Here is what to do now.")
        when 'successful'
            if AlaveteliConfiguration::donation_url.blank?
                _(" ")
            else
                _(" ",
                    :site_name => site_name, :donation_url => AlaveteliConfiguration::donation_url)
            end
        when 'partially_successful'
            if AlaveteliConfiguration::donation_url.blank?
                _(" ")
            else
                _(" ",
                    :site_name => site_name, :donation_url => AlaveteliConfiguration::donation_url)
            end
        when 'waiting_clarification'
            _("Please write your follow up message containing the necessary clarifications below.")
        when 'gone_postal'
            nil
        when 'internal_review'
            _("<p>Thank you! Hopefully your wait isn't too long.</p><p>You should get a response within {{late_number_of_days}} days, or be told if it will take longer (<a href=\"{{review_url}}\">details</a>).</p>",:late_number_of_days => AlaveteliConfiguration.reply_late_after_days, :review_url => unhappy_url(info_request) + "#internal_review")
        when 'error_message', 'requires_admin'
            _("Thank you! We'll look into what happened and try and fix it up.")
        when 'user_withdrawn'
            _("If you have not done so already, please write a message below telling the authority that you have withdrawn your request. Otherwise they will not know it has been withdrawn.")
        end

        case info_request.calculate_status
        when 'waiting_response', 'waiting_response_overdue', 'not_held', 'successful',
            'internal_review', 'error_message', 'requires_admin'
            redirect_to request_url(info_request)
        when 'waiting_response_very_overdue', 'rejected', 'partially_successful', 'user_withdrawn'
            redirect_to request_url(info_request)
        when 'waiting_clarification'
            redirect_to respond_to_last_url(info_request)
        when 'gone_postal'
            redirect_to respond_to_last_url(info_request) + "?gone_postal=1"
        else
            if @@custom_states_loaded
                return self.theme_describe_state(info_request)
            else
                raise "unknown calculate_status #{info_request.calculate_status}"
            end
        end
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

end

