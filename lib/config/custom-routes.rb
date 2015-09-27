# Here you can override or add to the pages in the core website
Alaveteli::Application.routes.draw do

    resources :publications, :only => [:index, :show]
    
    get "stories", to: "publications#stories"
    get "videos", to: "publications#videos"
    get "news", to: "publications#news"
    
    scope '/admin', :as => 'admin' do
        resources :publications, :controller => 'admin_publications'
    end
end
