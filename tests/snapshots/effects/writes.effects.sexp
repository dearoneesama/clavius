(Block
  [(LocalFunction
     (Binder f$1)
     (Function
       [(ClvMarker)
        (ClvParam n false (ClvTypeName integer))
        (ClvPre
          (BinOp and
            (BinOp ge (Id n$2 :type int53) (Literal number 0 :type int53) :type boolean)
            (BinOp lt (Id n$2 :type int53) (Literal number 100 :type int53) :type boolean)
            :type boolean))]
       [(Binder n$2 :type int53)]
       false
       (Block
         [(Local [(Literal number 0 :type int53)] [(Binder sum$3 :type int53)])
          (Local [(Literal number 0 :type int53)] [(Binder count$4 :type int53)])
          (Local [(Literal number 1 :type int53)] [(Binder untouched$5 :type int53)])
          (While
            [(ClvDecrease [(Id n$2 :type int53)])]
            (BinOp gt (Id n$2 :type int53) (Literal number 0 :type int53) :type boolean)
            (Block
              [(Local [(Literal number 1 :type int53)] [(Binder step$6 :type int53)])
               (If
                 [(IfArm
                    (BinOp gt (Id n$2 :type int53) (Literal number 5 :type int53) :type boolean)
                    (Block
                      [(Set [(Id step$6 :type int53)] [(Literal number 2 :type int53)])
                       (Set
                         [(Id sum$3 :type int53)]
                         [(BinOp add
                            (Id sum$3 :type int53)
                            (Literal number 1 :type int53)
                            :type int53)])]))]
                 nil)
               (While
                 [(ClvDecrease [(Id step$6 :type int53)])]
                 (BinOp gt (Id step$6 :type int53) (Literal number 0 :type int53) :type boolean)
                 (Block
                   [(Set
                      [(Id count$4 :type int53)]
                      [(BinOp add
                         (Id count$4 :type int53)
                         (Literal number 1 :type int53)
                         :type int53)])
                    (Set
                      [(Id step$6 :type int53)]
                      [(BinOp sub
                         (Id step$6 :type int53)
                         (Literal number 1 :type int53)
                         :type int53)])])
                 :writes [count$4 step$6])
               (Set
                 [(Id sum$3 :type int53)]
                 [(BinOp add (Id sum$3 :type int53) (Id step$6 :type int53) :type int53)])
               (Set
                 [(Id n$2 :type int53)]
                 [(BinOp sub (Id n$2 :type int53) (Literal number 1 :type int53) :type int53)])])
            :writes [sum$3 count$4 n$2])
          (Fornum
            []
            (Literal number 1 :type int53)
            (Literal number 3 :type int53)
            nil
            (Binder i$7 :type int53)
            (Block
              [(Local [(Id i$7 :type int53)] [(Binder j$8 :type int53)])
               (Set
                 [(Id j$8 :type int53)]
                 [(BinOp add
                    (Id j$8 :type int53)
                    (Literal number 1 :type int53)
                    :type int53)])]))])))
   (Local [(Literal number 0)] [(Binder y$9)])
   (While
     []
     (BinOp lt (Id y$9) (Literal number 3))
     (Block [(Set [(Id y$9)] [(BinOp add (Id y$9) (Literal number 1))])]))
   (ClvRegion
     [(Local [(Literal number 0 :type int53)] [(Binder x$10 :type int53)])
      (Repeat
        [(ClvDecrease
           [(BinOp sub (Literal number 10 :type int53) (Id x$10 :type int53) :type int53)])]
        (Block
          [(Set
             [(Id x$10 :type int53)]
             [(BinOp add (Id x$10 :type int53) (Literal number 1 :type int53) :type int53)])])
        (BinOp ge (Id x$10 :type int53) (Literal number 10 :type int53) :type boolean)
        :writes [x$10])])])
