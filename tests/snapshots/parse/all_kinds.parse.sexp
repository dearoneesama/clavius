(Block
  [(Local
     [(Literal string "é你好")
      (Literal number 0x1F)
      (Literal true true)
      (Literal false false)
      (Literal nil nil)]
     [(Binder s) (Binder n) (Binder t) (Binder f) (Binder z)])
   (Local
     [(Table
        [(TableField nil (Literal number 1))
         (TableField nil (Literal number 2.5))
         (TableField (Literal string "k") (Literal string "v"))
         (TableField (Literal string "x y") (Literal number 1LL))
         (TableField (Id n) (Table []))])]
     [(Binder tbl)])
   (LocalFunction
     (Binder fact)
     (Function
       []
       [(Binder k)]
       false
       (Block
         [(If
            [(IfArm (BinOp le (Id k) (Literal number 1)) (Block [(Return [(Literal number 1)])]))
             (IfArm (BinOp eq (Id k) (Literal number 2)) (Block [(Return [(Literal number 2)])]))]
            (Block
              [(Return
                 [(BinOp mul
                    (Id k)
                    (Call (Id fact) nil [(BinOp sub (Id k) (Literal number 1))]))])]))])))
   (Set
     [(Index (Id tbl) (Literal string "add"))]
     [(Function
        []
        [(Binder a) (Binder b)]
        true
        (Block [(Return [(BinOp add (Id a) (Id b)) (Dots)])]))])
   (Set
     [(Index (Id tbl) (Literal string "len"))]
     [(Function [] [(Binder self)] false (Block [(Return [(UnOp len (Id self))])]))])
   (Set
     [(Index (Id tbl) (Literal string "x")) (Index (Id tbl) (Literal number 1))]
     [(UnOp unm (Id n)) (UnOp not (Id t))])
   (Call
     (Id print)
     nil
     [(Call (Id tbl) len [])
      (Call (Id s) sub [(Literal number 1) (Literal number 2)])
      (Paren (Call (Id fact) nil [(Literal number 3)]))
      (BinOp concat (Id s) (Literal string "x"))
      (BinOp div
        (BinOp mod (BinOp pow (Literal number 2) (Literal number 3)) (Literal number 2))
        (Literal number 1))
      (BinOp or (BinOp and (Id t) (Id f)) (Id z))
      (BinOp ne (Literal number 1) (Literal number 2))
      (BinOp and
        (BinOp and
          (BinOp and
            (BinOp lt (Literal number 1) (Literal number 2))
            (BinOp le (Literal number 1) (Literal number 2)))
          (BinOp gt (Literal number 1) (Literal number 2)))
        (BinOp ge (Literal number 1) (Literal number 2)))])
   (Block
     [(Local [(Literal number 0)] [(Binder i)])
      (While
        []
        (BinOp lt (Id i) (Literal number 3))
        (Block
          [(Set [(Id i)] [(BinOp add (Id i) (Literal number 1))])
           (If [(IfArm (BinOp eq (Id i) (Literal number 2)) (Block [(Break)]))] nil)]))
      (Repeat [] (Block [(Local [(Id i)] [(Binder j)])]) (BinOp gt (Id j) (Literal number 0)))])
   (Fornum
     []
     (Literal number 1)
     (Literal number 3)
     nil
     (Binder i)
     (Block [(Call (Id print) nil [(Id i)])]))
   (Fornum
     []
     (Literal number 3)
     (Literal number 1)
     (UnOp unm (Literal number 1))
     (Binder i)
     (Block [(Goto continue) (Label continue)]))
   (Forin
     []
     [(Call (Id pairs) nil [(Id tbl)])]
     [(Binder k) (Binder v)]
     (Block [(Call (Id print) nil [(Id k) (Id v)])]))
   (Call
     (Id print)
     nil
     [(Call
        (Index (Id tbl) (Literal string "add"))
        nil
        [(Literal number 1) (Literal number 2) (Literal number 3)])
      (Call (Id tostring) nil [(Literal string "s")])
      (Call (Id type) nil [(Table [(TableField nil (Literal number 1))])])])
   (ClvSpec
     [(LocalFunction (Binder same) (Function [] [(Binder x)] false (Block [(Return [(Id x)])])))])
   (ClvRegion
     [(Local [(BinOp sub (Literal number 1) (Literal number 2))] [(Binder m)])
      (ClvGhost [(Local [(Id m)] [(Binder g)])])
      (ClvAssert (BinOp eq (Id g) (Id m)))
      (ClvProof false [(Call (Id same) nil [(Id m)])])])
   (ClvLemma [(LocalFunction (Binder l) (Function [] [] false (Block [])))])
   (Return [(Id tbl)])])
