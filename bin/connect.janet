(use spork/http spork/json jhydro)

(math/seedrandom (os/time))
(def i (math/floor (* 98 (math/random))))
(print ((request :POST "http://127.0.0.1:8000/connect"
                 :body (encode {:name (string "DEVICE" (if (< i 10) "0") i)
                                :key (util/bin2hex (os/cryptorand 8))
                                :ip (string "192.168.0." (+ 100 i))})) :body))
