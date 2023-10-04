(declare-project
  :name "deviman"
  :description ```Web application for managing devices. ```
  :version "0.1.0"
  :dependencies ["spork"])

(declare-executable
  :name "deviman"
  :entry "deviman/init.janet")
