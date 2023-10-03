(import spork/httpf)
(import spork/htmlgen)
(use spork/misc)

(defn persist-store
  "Persists the store to the image file"
  []
  (ev/sleep 0)
  (spit (dyn :image-file) (make-image (dyn :store))))

(defn ip-address?
  "PEG grammar predicate for IP address"
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

(defn format-time
  "Convert an integer time since epoch to readable string."
  [time]
  (if-not time (break ""))
  (def {:hours hours
        :minutes minutes
        :seconds seconds
        :month month
        :month-day month-day
        :year year} (os/date (math/floor time) true))
  (string/format "%d-%.2d-%.2d %.2d:%.2d:%.2d"
                 year (inc month) (inc month-day)
                 hours minutes seconds))

(defn precise-time
  ```
  Returns precise time `t` with s, ms, us, ns precision
  as a string.
  ```
  [t]
  (def at (math/abs t))
  (string/format
    ;(cond
       (zero? t) ["0s"]
       (>= at 1) ["%.3fs" t]
       (>= at 1e-3) ["%.3fms" (* t 1e3)]
       (>= at 1e-6) ["%.3fus" (* t 1e6)]
       (>= at 1e-9) ["%.3fns" (* t 1e9)])))

(defn layout
  "Wraps content in the page layout."
  [content]
  @[htmlgen/doctype-html
    [:html {"lang" "en"}
     [:head
      [:meta {"charset" "UTF-8"}]
      [:meta {"name" "viewport"
              "content" "width=device-width, initial-scale=1.0"}]
      [:meta {"name" "description" "content" "Devices manager"}]
      [:title "DeviMan"]
      [:link {:rel "stylesheet" :href "https://unpkg.com/missing.css@1.1.1"}]
      [:style ":root {--line-length: 60rem}"]]
     [:body content
      [:script {:src "https://unpkg.com/hyperscript.org@0.9.11"}]
      [:script {:src "https://unpkg.com/htmx.org@1.9.6"}]]]])

(def- manager-form
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

(defn- devices-section
  [devices]
  [:section
   [:h3 "Devices (" (length devices) ")"]
   [:table
    [:tr [:th "Name"] [:th "Key"] [:th "Connected"] [:th "Timestamp"]]
    (seq [{:name n :key k :timestamp t :connected c} :in devices
          :let [ft (format-time t) fc (format-time c)]]
      [:tr [:td n] [:td k] [:td fc] [:td ft]])]])

(defn dashboard
  "Root page with dashboard"
  {:path "/"
   :route-doc
   ```
   Entry point to the device manager. Route designated for the web browsers.
   Does not take any parameters or body.
   ```}
  [&]
  (layout
    (if-let [s (dyn :store) {:ip ip :port port} s
             m (s :manager) {:name name} m]
      @[[:header
         {:class "f-row align-items:center justify-content:space-between"}
         [:h1 "Dashboard"]
         [:div "Running for " (precise-time (- (os/clock) (dyn :startup)))]]
        [:main
         [:p "Manager " [:strong name] " is present on " [:strong ip]]
         (if-let [devices (s :devices) _ (not (empty? devices))]
           (devices-section devices)
           [:p "There are not any devices, please connect them on "
            [:code "http://" ip ":" port "/connect"]])]]
      manager-form)))

(defn initialize
  "Initializes new manager"
  {:path "/initialize"
   :schema (props
             "name" :string
             "description" (or nil :string))
   :render-mime "text/html"}
  [req body]
  (put (dyn :store) :manager (map-keys keyword (req :data)))
  (ev/go persist-store)
  @[[:h2 "New manager initialized!"]
    [:a {:href "/"} "Go to Dashboard"]])

(defn connect
  "Connects new device"
  {:path "/connect"
   :route-doc
   ```
   Entry point for devices. Designated for programatic HTTP calls.
   ```
   :schema (props :name :string
                  :key :string
                  :ip (pred ip-address?))
   :render-mime "text/plain"}
  [req body]
  (def s (dyn :store))
  (if (s :manager)
    (let [t (os/clock)]
      (merge-into body
                  {:connected t
                   :timestamp t
                   :payloads @[(freeze body)]})
      (if-not ((dyn :store) :devices)
        (put s :devices @[body])
        (update s :devices array/push body))
      (ev/go persist-store)
      (string "OK " (body :name)))
    (string "FAIL")))

(def- web-server "Template server" (httpf/server))
(httpf/add-bindings-as-routes web-server)

(defn main
  "Runs the http server"
  [_ image-file]
  (def store (load-image (slurp image-file)))
  (setdyn :image-file image-file)
  (setdyn :store store)
  (setdyn :startup (os/clock))
  (-> web-server (httpf/listen (store :ip) (store :port))))
