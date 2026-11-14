(Block
  [(Local [(Literal number 1)] [(Binder x$1)])
   (Local [(BinOp add (Id x$1) (Literal number 1))] [(Binder x$2)])
   (Block [(Local [(Id x$2)] [(Binder x$3)]) (Local [(Id x$3)] [(Binder y$4)])])
   (LocalFunction
     (Binder f$5)
     (Function
       [(Binder n$6)]
       false
       (Block
         [(Return
            [(BinOp add
               (Call (Id f$5) nil [(BinOp sub (Id n$6) (Literal number 1))])
               (Id x$2))])])))
   (Local [(Function [(Binder n$7)] false (Block [(Return [(Id g)])]))] [(Binder g$8)])
   (Fornum
     (Id x$2)
     (Literal number 10)
     nil
     (Binder i$9)
     (Block [(Local [(Id i$9)] [(Binder i$10)])]))
   (Forin
     [(Call (Id pairs) nil [(Table [])])]
     [(Binder k$11) (Binder v$12)]
     (Block [(Call (Id print) nil [(Id k$11) (Id v$12) (Id f$5) (Id g$8)])]))
   (Repeat (Block [(Local [(Literal number 1)] [(Binder r$13)])]) (Id r$13))
   (ClvRegion
     [(Local [(Literal number 1)] [(Binder a$14)])
      (Block [(Local [(BinOp add (Id a$14) (Literal number 1))] [(Binder a$15)])])
      (Set [(Id a$14)] [(BinOp add (Id a$14) (Literal number 1))])])
   (Call (Id print) nil [(Id a$14) (Id y)])])
