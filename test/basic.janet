(import ../deviman/init :as dm)
(use spork/test)

(defmacro assert-equals
  [a &opt b]
  (if b
    ~(assert (= ,a ,b) (string "It must be " (string/format "%m" ,b) ", but is " (string/format "%m" ,a)))
    ~(assert ,b (string "It must be " (string/format "%n" ,a)))))

(start-suite "Documentation")
(assert-docs "../deviman/init")
(end-suite)

(start-suite "Unit")
(assert (dm/ip-address? "192.168.0.1"))
(assert (not (dm/ip-address? "192.168.0.1g")))
(assert-equals (dm/format-time 1696321760.4321) "2023-10-03 10:29:20.4321")
(assert-equals (dm/precise-time 791663.478) "1w 2d 3h 54m 23.478s")
(assert-equals (dm/precise-time 91663.478) "1d 1h 27m 43.478s")
(assert-equals (dm/precise-time 87663.478) "1d 21m 3.478s")
(assert-equals (dm/precise-time 3663.478) "1h 1m 3.478s")
(assert-equals (dm/precise-time 63.478) "1m 3.478s")
(assert-equals (dm/precise-time 1.478) "1.478s")
(assert-equals (dm/precise-time 0.01478) "14.780ms")
(assert-equals (dm/precise-time 0.00001478) "14.780us")
(assert-equals (dm/precise-time 0.00000001478) "14.780ns")
(end-suite)
