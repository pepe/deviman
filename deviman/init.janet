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
  (string/format "%d-%.2d-%.2d %.2d:%.2d:%.2d.%.3d"
                 year (inc month) (inc month-day)
                 hours minutes seconds (math/floor (* 1000 (mod time 1)))))

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
(def <o>
  ```
  View prototype.
  
  This prototype is set to the main store. Its methods are only access points 
  from the http handlers in to the store. Methods should be domain specific
  getters of the data inside the store datastructure.
  ```
  @{:devices @{}})

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

(def logo
  (htmlgen/html
    @[[:svg
       {:xmlns "http://www.w3.org/2000/svg"
        :width 45
        :height 45
        :viewBox "0 0 45 45"}
       [:g
        [:rect
         {:x 2 :y 2 :width 40 :height 40 :rx 5
          :fill "white" :stroke "black" :stroke-width 2}]
        [:text {:x 7 :y 25 :font-size 24 :font-weight "bold"}
         [:tspan {:rotate -15 :dx 2} "D"]
         [:tspan {:dx -15 :rotate 15 :dy 9} "M"]]]]]))

(defn layout
  ```Wraps content in the page layout.```
  [desc header main]
  (htmlgen/raw 
   (htmlgen/html
    @[htmlgen/doctype-html
      [:html {"lang" "en"}
       [:head
        [:meta {"charset" "UTF-8"}]
        [:meta {"name" "viewport"
                "content" "width=device-width, initial-scale=1.0"}]
        [:meta {"name" "description"
                "content" (string "DeviMan - Devices manager - " desc)}]
        [:title "DeviMan"]
        [:link {:rel "stylesheet" :href "/missing.css"}]
        [:link {:rel "icon" :type "image/svg+xml" :href "/favicon.svg"}]
        [:style ":root {--line-length: 60rem}"]]
       [:body
        [:header
         {:class "f-row align-items:center justify-content:space-between"}
         (htmlgen/raw logo)
         header]
        [:main main]
        [:script {:src "hyperscript.js"}]
        [:script {:src "htmx.js"}]]]])))

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
            (do
              (put store :manager (map-keys keyword manager))
              (ev/give webvisor [:refresh :manager]))
            [:device device]
            (let [key (device :key)]
              (update store :devices put key
                    (merge-into device
                                {:connected time
                                 :timestamp time
                                 :payloads @[[time (freeze device)]]}))
              (ev/give webvisor [:refresh :devices])
              (ev/give webvisor [:refresh [:device key]]))
            [:payload payload]
            (let [key (payload :key)
                  device-path [:devices key]]
              (-> store
                  (put-in [;device-path :timestamp] time)
                  (update-in [;device-path :payloads]
                             array/push [time (freeze payload)]))
              (ev/give webvisor [:refresh [:device key]])))
          (journal time directive)
          (dirty store))
        [:refresh view]
        (match view
          :initialize
          (put <o> :index
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
                    [:button "Submit"]]]))
          :manager
          (let [{:ip ip :port port :manager manager} store
                {:name name} manager]
            (merge-into <o>
                        {:index
                         (layout
                           "Manager connection"
                           [:h1 "Dashboard"]
                           @[[:p "Manager " [:strong name] " is present on " [:strong ip]]
                             [:p "There are not any devices, please connect them on "
                              [:code "http://" ip ":" port "/connect"]]])
                         :manager manager}))
          :devices 
          (let [{:ip ip :port port :manager {:name name} :devices devices} store]
            (put <o> :index
                 (layout
                  "List of devices"
                  [:h1 "Dashboard"]
                  @[[:p "Manager " [:strong name] " is present on " [:strong ip]]
                    [:section
                     [:h3 "Devices (" (length devices) ")"]
                     [:div [:a {:_ "on click remove <[data-role=payloads] td/>"}
                            "Collapse all details"]]
                     [:table {:class "width:100%"}
                      [:tr [:th "Key"] [:th "Name"] [:th "IP"] [:th "Connected"]]
                      (seq [{:name n :key k :ip ip :connected c} :in devices]
                        @[[:tr
                           [:td [:a {:hx-get (string "/device?key=" k)
                                     :hx-target "next tr[data-role='payloads']"
                                     :hx-swap "outerHTML"} k]]
                           [:td n] [:td ip] [:td (format-time c)]]
                          [:tr {:data-role "payloads"}]])]]])))
          [:device key]
          (let [{:devices devices} store
                {:name n :timestamp t :connected c :payloads ps} (get devices key)]
            (update <o> :devices put key
                    [:tr {:data-role "payloads" :_ "on click remove <td/> from me"}
                     [:td {:colspan "4"}
                      [:table {:class "width:100%"}
                       [:tr [:th "Timestamp"] [:th "Payload"]]
                       (seq [[ts d] :in ps]
                         [:tr [:td (format-time ts)] [:td (string/format "%m" d)]])]]])))))))

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
    (var drain false)
    (var journaled 0)
    (forever
      (match (ev/take datavisor)
        [:dirty store]
        (if-not drain
          (ev/spawn
            (set drain true)
            (ev/sleep 5)
            (set drain false)
            (with [f (file/open image-file :wb)] (file/write f (make-image store)))
            (ev/give datavisor [:remove-journal])))
        [:journal time entry]
        (with [f (file/open (journal-name journaled) :wb)]
          (file/write f (marshal [time entry]))
          (++ journaled))
        [:remove-journal]
        (do
          (loop [i :range [journaled]] (os/rm (journal-name i)))
          (set journaled 0)))
      (gccollect))))

# HTT
(defn static-missing-css
  "Serve missing.css from memory"
  {:path "/missing.css"
   :render-mime "text/css"}
  [&]
  (put (dyn :response-headers) "cache-control" "max-age=3600")
  (comptime (slurp (path/join (path/dirname (dyn :current-file))
                              "static/missing.css"))))

(defn static-hyperscript-js
  "Serve hyperscript.js from memory"
  {:path "/hyperscript.js"
   :render-mime "text/javascript"}
  [&]
  (put (dyn :response-headers) "cache-control" "max-age=3600")
  (comptime (slurp (path/join (path/dirname (dyn :current-file))
                              "static/hyperscript.js"))))

(defn static-htmx-js
  "Serve htmx.js from memory"
  {:path "/htmx.js"
   :render-mime "text/javascript"}
  [&]
  (put (dyn :response-headers) "cache-control" "max-age=3600")
  (comptime (slurp (path/join (path/dirname (dyn :current-file))
                              "static/htmx.js"))))

(defn static-svg-icon
  "Serve favicon from memory"
  {:path "/favicon.svg"
   :render-mime "image/svg+xml"}
  [&]
  (put (dyn :response-headers) "cache-control" "max-age=3600")
  logo)

(defn dashboard
  "Root page with dashboard"
  {:path "/"
   :route-doc
   ```
   Entry point to the device manager. Route designated for the web browsers.
   Does not take any parameters or body.
   ```}
  [&]
  (<o> :index))

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
   ```Entry point for devices. Designated for programatic HTTP calls.
   ``` :schema (props :name :string
                      :key :string
                      :ip (pred ip-address?))
   :render-mime "text/plain"}
  [_ body]
  (def key (body :key))
  (assert  (<o> :manager) (string "FAIL " key))
  (>>> :device body)
  (string "OK " key))

(defn device
  "Device detail fragment"
  {:path "/device"
   :route-doc
   ```
    Details of the device. Designated for htmx calls.
    ```}
  [{:query {"key" key}} _]
  (get-in <o> [:devices key]))

(defn payload
  "Receives and saves payload from a device. 
  Designated for programatic HTTP calls."
  {:path "/payload"
   :schema (props :key :string)
   :render-mime "text/plain"}
  [_ body]
  (def key (body :key))
  (assert ((<o> :devices) key) "FAIL")
  (>>> :payload body)
  (string "OK " key))

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
  (if (not (store :manager))
    (ev/give webvisor [:refresh :initialize])
    (do
      (ev/give webvisor [:refresh :manager])
      (when-let [devices (store :devices)
               _ (not (empty? devices))]
        (ev/give webvisor [:refresh :devices])
        (each d devices (ev/give webvisor [:refresh [:device (d :key)]])))))
  (ev/go (web-server (store :ip) (store :port)) web-state webvisor)
  (ev/spawn (eprint "All systems are up")))
