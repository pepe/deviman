(import ../deviman/init :as dm)
(use spork/test)

(defmacro assert-equals
  [a &opt b]
  (if b
    ~(assert (= ,a ,b) (string "It must be " (string/format "%m" ,a) ", but is " (string/format "%m" ,b)))
    ~(assert ,b (string "It must be " (string/format "%n" ,a)))))

(start-suite "Documentation")
(assert-docs "../deviman/init")
(end-suite)

(start-suite "Unit")
(assert (dm/ip-address? "192.168.0.1"))
(assert (not (dm/ip-address? "192.168.0.1g")))
(assert-equals (dm/format-time 1696321760) "2023-10-03 10:29:20")
(assert-equals (dm/precise-time 1) "1.000s")
(assert-equals (dm/precise-time 0.01) "10.000ms")
(assert-equals (dm/precise-time 0.00001) "10.000us")
(assert-equals (dm/precise-time 0.00000001) "10.000ns")
(end-suite)
