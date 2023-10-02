(use spork/http spork/json spork/misc)

(defn main [_ &opt count]
  (default count "1")
  (repeat (scan-number count)
    (math/seedrandom (string/format "%f" (mod (os/clock) 1)))
    (def i (math/floor (* 98 (math/random))))
    (print ((request :POST "http://127.0.0.1:8000/connect"
                     :body (encode {:name (string "DEVICE" (if (< i 10) "0") i)
                                    :key (make-id)
                                    :ip (string "192.168.0." (+ 100 i))})) :body))))
