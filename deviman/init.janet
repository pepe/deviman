(import spork/httpf)
(import spork/htmlgen)
(import spork/sh)
(import spork/path)
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
  (string/format "%d-%.2d-%.2d %.2d:%.2d:%.2d.%.0f"
                 year (inc month) (inc month-day)
                 hours minutes seconds (* 10000 (mod time 1))))

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
       (>= at 604800)
       ["%iw %s" (div at 604800) (precise-time (mod t 604800))]
       (>= at 86400)
       ["%id %s" (div at 86400) (precise-time (mod t 86400))]
       (>= at 3600)
       ["%ih %s" (div at 3600) (precise-time (mod t 3600))]
       (>= at 60)
       ["%im %s" (div at 60) (precise-time (mod t 60))]
       (>= at 1) ["%.3fs" t]
       (>= at 1e-3) ["%.3fms" (* t 1e3)]
       (>= at 1e-6) ["%.3fus" (* t 1e6)]
       (>= at 1e-9) ["%.3fns" (* t 1e9)])))

# Data
(def View
  ```
  View prototype.
  
  This prototype is set to the main store. Its methods are only access points 
  from the http handlers in to the store. Methods should be domain specific
  getters of the data inside the store datastructure.
  ```
  @{:ip-port (fn get-ip-port [view]
               [(gett view :_store :ip) (gett view :_store :port)])
    :manager (fn get-manager [view] (gett view :_store :manager))
    :devices (fn get-devices [view &named sorted-by]
               (cond-> (gett view :_store :devices)
                       sorted-by (->> values
                                      (sort-by |(- ($ sorted-by))))))})

(defmacro >>>
  "Give the time, key and data to the supervisor. Semantic macro."
  [key & data]
  ~(ev/give-supervisor :process (os/clock) [,key ,;data]))

(defmacro- dirty
  ```
  Notifies supervisor about the dirty store. Semantic macro.
  ```
  [store]
  ~(ev/give-supervisor :dirty ,store))

(defmacro- journal
  ```
  Notifies supervisor about the journal entry. Semantic macro.
  ```
  [time entry]
  ~(ev/give-supervisor :journal ,time ,entry))

(defn data-processor
  ```
  Function for creating data processor fiber.

  Operations invoked with `>>>` are taken by the supervisor
  and processed in this function. These operations are the only way
  for http handlers to modify the store datastructure.
  ```
  [store]
  (fn data-processor [webvisor]
    (eprint "Data processor is running")
    (forever
      (match (ev/take webvisor)
        [:process time directive]
        (do
          (match directive
            [:manager manager]
            (put store :manager (map-keys keyword manager))
            [:device device]
            (update store :devices put (device :key)
                    (merge-into device
                                {:connected time
                                 :timestamp time
                                 :payloads @[[time (freeze device)]]}))
            [:payload payload]
            (let [dp [:devices (payload :key)]]
              (-> store
                  (put-in [;dp :timestamp] time)
                  (update-in [;dp :payloads]
                             array/push [time (freeze payload)]))))
          (journal time directive)
          (dirty store))))))

(defn journal-name
  "Creates journal name with `index`."
  [index]
  (string/format "journal%i.jimage" index))

(defn store-persistor
  ```
  Function for creating data manager fiber. 
  
  In this function every second, the store is persisted to the jimage file.
  ```
  [image-file]
  (fn store-persistor [datavisor]
    (eprint "Store persistor is running")
    (def drain (ev/chan 1))
    (var journaled 0)
    (forever
      (match (ev/take datavisor)
        [:dirty store]
        (if-not (ev/full drain)
          (ev/spawn
            (ev/give drain :full)
            (ev/sleep 5)
            (ev/take drain)
            (def i (make-image store))
            (with [f (os/open image-file :w)] (ev/write f i))
            (ev/give datavisor [:remove-journal])))
        [:journal time entry]
        (with [f (os/open (journal-name journaled) :wc)]
          (ev/write f (marshal [time entry]))
          (++ journaled))
        [:remove-journal]
        (do
          (loop [i :range [journaled]] (os/rm (journal-name i)))
          (set journaled 0)))
      (gccollect))))

# HTTP
(var <o> "Forward reference to view." nil)

(defn static-png-icon
  "Serve favicon from memory"
  {:path "/favicon.png"
   :render-mime "image/png"}
  [&]
  (put (dyn :response-headers) "cache-control" "max-age=3600")
  (comptime (slurp (path/join (path/dirname (dyn :current-file))
                              "static/favicon.png"))))

(def logo
  (slurp (path/join (path/dirname (dyn :current-file)) "static/favicon.svg")))

(defn static-svg-icon
  "Serve favicon from memory"
  {:path "/favicon.svg"
   :render-mime "image/svg+xml"}
  [&]
  (put (dyn :response-headers) "cache-control" "max-age=3600")
  logo)

(defn layout
  ```
  Wraps content in the page layout.
  ```
  [desc header main]
  @[htmlgen/doctype-html
    [:html {"lang" "en"}
     [:head
      [:meta {"charset" "UTF-8"}]
      [:meta {"name" "viewport"
              "content" "width=device-width, initial-scale=1.0"}]
      [:meta {"name" "description"
              "content" (string "DeviMan - Devices manager - " desc)}]
      [:title "DeviMan"]
      [:link {:rel "stylesheet" :href "https://unpkg.com/missing.css@1.1.1"}]
      [:link {:rel "icon" :type "image/svg+xml" :href "/favicon.svg"}]
      [:link {:rel "icon" :type "image/png" :href "/favicon.png"}]
      [:style ":root {--line-length: 60rem}"]]
     [:body
      [:header
       {:class "f-row align-items:center justify-content:space-between"}
       (htmlgen/raw logo)
       header]
      [:main main]
      [:script {:src "https://unpkg.com/hyperscript.org@0.9.11"}]
      [:script {:src "https://unpkg.com/htmx.org@1.9.6"}]]]])

(defn dashboard
  "Root page with dashboard"
  {:path "/"
   :route-doc
   ```
   Entry point to the device manager. Route designated for the web browsers.
   Does not take any parameters or body.
   ```}
  [&]
  (def [ip port] (:ip-port <o>))
  (if-let [{:name name} (:manager <o>)]
    (layout
      "List of devices"
      @[[:h1 "Dashboard"]
        [:div "Running for " (precise-time (- (os/clock) (dyn :startup)))]]
      @[[:p "Manager " [:strong name] " is present on " [:strong ip]]
        (if-let [devices (:devices <o> :sorted-by :connected)
                 _ (not (empty? devices))]
          [:section
           [:h3 "Devices (" (length devices) ")"]
           [:div [:a {:_ "on click remove <[data-role=payloads]/>"}
                  "Collapse all details"]]
           [:table {:class "width:100%"}
            [:tr [:th "Key"] [:th "Name"] [:th "IP"] [:th "Connected"]]
            (seq [{:name n :key k :ip ip :connected c} :in devices]
              [:tr
               [:td [:a {:hx-get (string "/device?key=" k)
                         :hx-target "closest tr"
                         :hx-swap "afterend"} k]]
               [:td n] [:td ip] [:td (format-time c)]])]]
          [:p "There are not any devices, please connect them on "
           [:code "http://" ip ":" port "/connect"]])])
    (layout
      "Manager inicialization"
      [:h1 "Initialization"]
      @[[:h2 "Configure new manager"]
        [:p
         {:class "error bad box"
          :style "display: none"
          :_ ``
             on click
               put '' into me
               hide me
             ``}]
        [:form
         {:class "table rows box"
          :hx-post "/initialize"
          :hx-target "main"
          :_ ``
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
         [:button "Submit"]]])))

(defn initialize
  "Initializes new manager"
  {:path "/initialize"
   :schema (props
             "name" :string
             "description" (or nil :string))
   :render-mime "text/html"}
  [{:data data} _]
  (>>> :manager data)
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
  [_ body]
  (if (:manager <o>)
    (do
      (>>> :device body)
      (string "OK " (body :key)))
    (error "FAIL")))

(defn device
  "Device detail fragment"
  {:path "/device"
   :route-doc
   ```
    Details of the device. Designated for htmx calls.
    ```}
  [{:query {"key" key}} _]
  (def {:name n :key k :timestamp t :connected c :payloads ps}
    ((:devices <o>) key))
  [:tr {:data-role "payloads" :_ "on click remove me"}
   [:td {:colspan "4"}
    [:table {:class "width:100%"}
     [:tr [:th "Timestamp"] [:th "Payload"]]
     (seq [[ts d] :in ps]
       [:tr [:td (format-time ts)] [:td (string/format "%m" d)]])]]])

(defn payload
  "Receives and saves payload from a device. 
  Designated for programatic HTTP calls."
  {:path "/payload"
   :schema (props :key :string)
   :render-mime "text/plain"}
  [_ body]
  (def key (body :key))
  (if ((:devices <o>) key)
    (do
      (>>> :payload body)
      (string "OK " key))
    "FAIL"))

(defn ping
  "Ping"
  {:path "/ping"
   :render-mime "text/plain"}
  [&] "pong")

(def- web-state "Template server" (httpf/server))
(httpf/add-bindings-as-routes web-state)

(defn web-server
  "Function for creating web server fiber."
  [ip port]
  (fn [web-state]
    (eprin "HTTP server is ")
    (httpf/listen web-state ip port 1)))

(defn check-journal
  "Check if journal exists, and restores it, when it does."
  []
  (when (os/stat (journal-name 0))
    (eprint "Journal found")
    (var i 0)
    (var jf (journal-name i))
    (var im "")
    (while (os/stat jf)
      (eprint "Restoring " jf)
      (with [f (os/open jf)]
        (set im (ev/read f :all)))
      (os/rm jf)
      (ev/give-supervisor :process ;(unmarshal im))
      (set jf (journal-name (++ i))))))

(defn main
  "Runs the http server."
  [_ image-file]
  (setdyn :startup (os/clock))
  (def store (load-image (slurp image-file)))
  (eprint "Store is loaded from file " image-file)
  (def webvisor (ev/chan 1024))
  (def datavisor (ev/chan 1024))
  (ev/go (data-processor store) webvisor datavisor)
  (ev/go (store-persistor image-file) datavisor)
  (ev/go check-journal nil webvisor)
  (set <o> (table/setproto @{:_store store} View))
  (ev/go (web-server (store :ip) (store :port)) web-state webvisor)
  (ev/spawn (eprint "All systems are up")))
