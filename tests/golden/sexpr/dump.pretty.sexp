(Local
  [(Binder y$2 :type int53)]
  [(BinOp add
     (Id x$1 :type int53)
     (Literal number 1 :type int53)
     :type int53)]
  :rec false)
(Unit main
  (Assume A1 (is_int53 x$1))
  (Check O1 (is_int53 (+ x$1 1)))
  (Assign y$2 (+ x$1 1)))
(obligation O1 :kind range :node 5)
(assumption A1 :kind type_fact :node 2)
(Literal string "a \"quoted\"\nstring")
