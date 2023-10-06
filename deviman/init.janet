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
                                      (sort-by |(get $ sorted-by)))))})

(defmacro >>>
  "Give the key and data to the supervisor. Semantic macro."
  [key & data]
  ~(ev/give-supervisor :process [,key ,;data]))

(defmacro- dirty
  ```
  Notifies supervisor about the dirty store. Semantic macro.
  ```
  [store]
  ~(ev/give-supervisor :dirty ,store))

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
        [:process directive]
        (do
          (match directive
            [:manager manager]
            (put store :manager (map-keys keyword manager))
            [:device device]
            (let [now (os/clock)]
              (update store :devices put (device :key)
                      (merge-into device
                                  {:connected now
                                   :timestamp now
                                   :payloads @[[now (freeze device)]]})))
            [:payload payload]
            (let [now (os/clock)
                  dp [:devices (payload :key)]]
              (-> store
                  (put-in [;dp :timestamp] now)
                  (update-in [;dp :payloads]
                             array/push [now (freeze payload)]))))
          (dirty store))))))

(defn store-persistor
  ```
  Function for creating data manager fiber. 
  
  In this function every second, the store is persisted to the jimage file.
  ```
  [image-file]
  (fn store-persistor [datavisor]
    (eprint "Store persistor is running")
    (def drain (ev/chan 1))
    (forever
      (match (ev/take datavisor)
        [:dirty store]
        (do
          (ev/give drain :empty)
          (ev/sleep 1)
          (eprin "Persisting ")
          (def start (os/clock))
          (while (not (= :empty (last (ev/select datavisor drain)))))
          (def i (make-image store))
          (eprin (/ (length i) 1024) "KB")
          (with [f (os/open image-file :w)] (ev/write f i))
          (eprint " done in " (precise-time (- (os/clock) start)))))
      (gccollect))))

# HTTP
(var <o> "Forward reference to view." nil)

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
      [:style ":root {--line-length: 60rem}"]]
     [:body
      [:header
       {:class "f-row align-items:center justify-content:space-between"}
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
        (if-let [devices (:devices <o> :sort-by :connected)
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
  (fn [web-state] (httpf/listen web-state ip port 1)))

(defn main
  "Runs the http server."
  [_ image-file]
  (setdyn :startup (os/clock))
  (def store (load-image (slurp image-file)))
  (eprint "Store is loaded from file " image-file)
  (set <o> (table/setproto @{:_store store} View))
  (def webvisor (ev/chan 1024))
  (eprin "HTTP server is ")
  (ev/go (web-server (store :ip) (store :port)) web-state webvisor)
  (def datavisor (ev/chan 1024))
  (ev/go (data-processor store) webvisor datavisor)
  (ev/go (store-persistor image-file) datavisor)
  (ev/spawn (eprint "All systems are up")))
