(import spork/httpf)
(import spork/htmlgen)
(use spork/misc)

(defn persist-store
  []
  "Saves the store to the image file"
  (spit (dyn :image-file) (make-image (dyn :store))))

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

(def manager-form
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
      [:p
       [:label {:for "name"} "Name"]
       [:input {:name "name" :required true}]]
      [:p
       [:label {:for "description"} "Description"]
       [:textarea {:name "description"}]]
      [:button "Submit"]]]])

(defn dashboard
  "Root page with dashboard"
  {:path "/"
   :route-doc
   ```
   Entry point to the device manager. Route designated for the web browsers.
   Does not take any parameters or bodies.
   ```}
  [&]
  (layout
    (if-let [store (dyn :store) {:ip ip :port port} store
             manager (store :manager) {:name name} manager]
      @[[:header [:h1 "Dashboard"]]
        [:main
         [:p "Manager " [:strong name] " is present on " [:strong ip]]
         [:section
          [:h3 "Devices"]
          (if-let [devices (store :devices) _ (not (empty? devices))]
            [:p "There will be devices list"]
            [:p "There are not any devices, please connect them on "
             [:code ip ":" port "/connect"]])]]]
      manager-form)))

(defn initialize
  "Initializes new manager"
  {:path "/initialize"
   :schema (props
             "name" :string
             "description" (or nil :string))
   :render-mime "text/html"}
  [req body]
  (ev/spawn
    (save :manager (req :data))
    (persist-store))
  @[[:h2 "New manager initialized!"]
    [:a {:href "/"} "Go to Dashboard"]])

(defn main
  "Runs the http server"
  [_ image-file]
  (def store (load-image (slurp image-file)))
  (setdyn :image-file image-file)
  (setdyn :store store)
  (-> (httpf/server)
      httpf/add-bindings-as-routes
      (httpf/listen (store :ip) (store :port))))
