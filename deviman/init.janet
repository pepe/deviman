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

(defn ip-address?
  "PEG grammar for IP address"
  [str]
  (peg/match
    '{:dig (range "09")
      :0-4 (range "04")
      :0-5 (range "05")
      :byte (choice
              (sequence "25" :0-5)
              (sequence "2" :0-4 :dig)
              (sequence "1" :dig :dig)
              (between 1 2 :dig))
      :main (sequence :byte "." :byte "." :byte "." :byte -1)} str))

(defn layout
  "Wraps content in layout"
  [content]
  @[htmlgen/doctype-html
    [:html
     [:head
      [:title "DeviMan"]
      [:link {:rel "stylesheet" :href "https://unpkg.com/missing.css@1.1.1"}]]
     [:body content
      [:script {:src "https://unpkg.com/hyperscript.org@0.9.11"}]
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
         [:p {:class "error bad box"
              :style "display: none"
              :_ "on click 
                    put `` into me
                    hide me"}]
         [:form {:class "table rows box"
                 :hx-post "/initialize"
                 :hx-target "main"
                 :_ "on htmx:responseError
                      set text to the event's detail's xhr's response
                      put text into .error
                      show .error"}
          [:p [:label {:for "name"} "Name"]
           [:input {:name "name" :required true}]]
          [:p [:label {:for "ip"} "IP address"]
           [:input {:name "ip" :required true}]]
          [:button "Submit"]]]])))

(defn initialize
  "Initializes new manager"
  {:path "/initialize"
   :schema (props
             "name" :string
             "ip" (pred ip-address?))
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
