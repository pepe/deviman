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
     [:body content]]])

(defn dashboard
  "Root page with dashboard"
  {:path "/"}
  [&]
  (layout
    (if ((dyn :store) :manager)
      @[[:header [:h1 "Dashboard"]]
        [:main
         [:p "There will be all controlls for the application"]]]
      @[[:header [:h1 "Initialization"]]
        [:main
         [:p "There will be an manager initialization wizard"]]])))

(defn main
  "Runs the http server"
  [&]
  (setdyn :store (or (load-image (slurp "store.jimage")) @{}))
  (-> (httpf/server)
      httpf/add-bindings-as-routes
      httpf/listen))
