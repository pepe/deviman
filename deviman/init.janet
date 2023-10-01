(import spork/httpf)
(import spork/htmlgen)
(use spork/misc)

(def image-file "store.jimage")

(defn persist-store
  []
  "Saves the store to the image file"
  (spit image-file (make-image (dyn :store))))

(defn save
  "Save a `value` under a `key` in store. `value`'s keys get keywordized."
  [key value]
  (put (dyn :store) key (map-keys keyword value)))
(defn layout
  "Wraps content in layout"
  [content]
  @[htmlgen/doctype-html
    [:html
     [:head
      [:title "DeviMan"]
      [:link {:rel "stylesheet" :href "https://unpkg.com/missing.css@1.1.1"}]]
     [:body content
      [:script {:src "https://unpkg.com/htmx.org@1.9.6"}]]]])

(defn dashboard
  "Root page with dashboard"
  {:path "/"}
  [&]
  (layout
    (if ((dyn :store) :manager)
      (let [{:name name :ip ip} ((dyn :store) :manager)]
        @[[:header [:h1 "Dashboard"]]
          [:main
           [:p "Manager " [:strong name] " is present on " [:strong ip]]]])
      @[[:header [:h1 "Initialization"]]
        [:main
         [:h2 "Configure new manager"]
         [:form {:class "table rows box"
                 :hx-post "/initialize"
                 :hx-target "main"}
          [:p [:label {:for "name"} "Name"]
           [:input {:name "name" :required true}]]
          [:p [:label {:for "ip"} "IP address"]
           [:input {:name "ip" :required true}]]
          [:button "Submit"]]]])))

(defn initialize
  "Initializes new manager"
  {:path "/initialize"
   :render-mime "text/html"}
  [req body]
  (ev/spawn
    (save :manager (req :data))
    (persist-store))
  @[[:h2 "New manager initialized!"]
    [:a {:href "/"} "Go to Dashboard"]])

(defn main
  "Runs the http server"
  [&]
  (setdyn :store (or (load-image (slurp image-file)) @{}))
  (-> (httpf/server)
      httpf/add-bindings-as-routes
      httpf/listen))
