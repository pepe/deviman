(use spork/http spork/json spork/misc)

(defn main
  "Simple program for simulating device connection."
  [_ key]
  (math/seedrandom (string/format "%f" (mod (os/clock) 1)))
  (def i (math/floor (* 98 (math/random))))
  (print ((request :POST "http://127.0.0.1:8000/payload"
                   :body
                   (encode {:key key
                            :unit "V"
                            :value i})) :body)))
