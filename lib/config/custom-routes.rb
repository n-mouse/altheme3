# Here you can override or add to the pages in the core website
Alaveteli::Application.routes.draw do

    get 'ruins', to: 'sandbox#domiki'
    get 'covid', to: 'sandbox#covid'
    get 'hto', to: 'publications#hto'
    
    post '/tinymce_assets' => 'tinymce_assets#create'
        
    resources :publications, :only => [:index]

    resources :commentaries, :only => [:new, :edit, :create, :update, :destroy, :index]
    
    scope '/nasud' do
        get '/', to: 'sandbox#nasud', as: 'nasud'
        resources :violations, :only => [:new, :create]
        resources :cases, :only => [:show]
        resources :donations, :only => [:new, :create]
    end

    scope '/admin', :as => 'admin' do
        resources :publications, :controller => 'admin_publications'
        resources :commentaries, :controller => 'admin_commentaries'
        scope '/nasud' do
          get '/', to: 'admin_general#nasud'
          resources :cases, :controller => 'admin_cases'
          resources :violations, :controller => 'admin_violations'
          resources :donations, :controller => 'admin_donations'
		end
    end
    
    get '/admin/nasud', to: 'admin_general#nasud'


end
