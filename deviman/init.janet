(import spork/httpf)
(import spork/htmlgen)

(defn layout
  "Wraps content in layout"
  [content]
  @[htmlgen/doctype-html
    [:html
     [:head
      [:title "DeviMan"]
      [:link {:rel "stylesheet" :href "https://unpkg.com/missing.css@1.1.1"}]]
     [:body
      content]]])

(defn dashboard
  "Root page with dashboard"
  {:path "/"}
  [&]
  (layout
    @[[:header [:a {:href "/"} [:h1 "Dashboard"]]]
      [:main
       [:p "There will be all the controlls for the application"]]]))

(defn main
  "Runs the http server"
  [&]
  (-> (httpf/server)
      httpf/add-bindings-as-routes
      httpf/listen))
