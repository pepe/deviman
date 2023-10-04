(import spork/httpf)
(import spork/htmlgen)
(use spork/misc)

# Utility
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

# Data
(def View
  "View prototype"
  @{:ip-port (fn get-manager [view]
               [(gett view :_store :ip) (gett view :_store :port)])
    :manager (fn get-manager [view] (gett view :_store :manager))
    :devices (fn get-devices [view] (gett view :_store :devices))})

(defn set-data
  "Give the key and data to the supervisor"
  [key & data]
  (ev/give-supervisor key ;data))

(defmacro do-dirty
  "Does `operation` on `store` and marks it dirty."
  [store & operation]
  ~(do
     ,(tuple (operation 0) store ;(tuple/slice operation 1))
     (put ,store :dirty true)))

(defn data-manager
  "Function for creating data manager fiber"
  [store]
  (fn [supervisor]
    (forever
      (match (ev/take supervisor)
        [:manager value]
        (do-dirty store put :manager value)
        [:device key device]
        (do-dirty store update :devices put key device)))))

(defn data-persistor
  "Function for creating data manager fiber"
  [image-file store]
  (forever
    (ev/sleep 1)
    (when (store :dirty)
      (eprin "Persisting ...")
      (put store :dirty nil)
      (spit image-file (make-image store))
      (gccollect))))

# HTTP
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
     [:body
      content
      [:script {:src "h9ttps://unpkg.com/hyperscript.org@0.9.11"}]
      [:script {:src "https://unpkg.com/htmx.org@1.9.6"}]]]])

(def- manager-form
  @[[:header [:h1 "Initialization"]]
    [:main
     [:h2 "Configure new manager"]
     [:p
      {:class "error bad box"
       :style "display: none"
       :_ ``
       on click
         put "" into me
         hide me
       ``}]
     [:form
      {:class "table rows box"
       :hx-post "/initialize"
       :hx-target "main"
       :_
       ``
       on htmx:responseError
         set text to the event's detail's xhr's response
         put text into .error
         show .error
       ``}
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
  (def view (dyn :view))
  (def [ip port] (:ip-port view))
  (layout
    (if-let [{:name name} (:manager view)]
      @[[:header
         {:class "f-row align-items:center justify-content:space-between"}
         [:h1 "Dashboard"]
         [:div "Running for " (precise-time (- (os/clock) (dyn :startup)))]]
        [:main
         [:p "Manager " [:strong name] " is present on " [:strong ip]]
         (if-let [devices (:devices view) _ (not (empty? devices))]
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
  (set-data :manager (map-keys keyword (req :data)))
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
  (if (:manager (dyn :view))
    (let [now (os/clock)]
      (merge-into body
                  {:connected now
                   :timestamp now
                   :payloads @[(freeze body)]})
      (set-data :device (body :key) body)
      (string "OK " (body :name)))
    (error "FAIL")))

(def- web-state "Template server" (httpf/server))
(httpf/add-bindings-as-routes web-state)

(defn web-server
  "Function for creating web server fiber"
  [ip port]
  (fn [web-state] (httpf/listen web-state ip port)))

(defn main
  "Runs the http server"
  [_ image-file]
  (setdyn :startup (os/clock))
  (def store (load-image (slurp image-file)))
  (setdyn :view (table/setproto @{:_store store} View))
  (def datavisor (ev/chan 10))
  (ev/go (web-server (store :ip) (store :port)) web-state datavisor)
  (ev/go (data-manager store) datavisor)
  (ev/go (data-persistor image-file store)))
