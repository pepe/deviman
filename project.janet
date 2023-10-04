(declare-project
  :name "deviman"
  :description ```Web application for managing devices. ```
  :version "0.1.1"
  :dependencies ["spork"])

(declare-executable
  :name "deviman"
  :entry "deviman/init.janet")
