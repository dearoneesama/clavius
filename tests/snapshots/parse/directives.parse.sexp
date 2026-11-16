(Block
  [(LocalFunction
     (Binder unmarked)
     (Function [] [(Binder n)] false (Block [(Return [(BinOp gt (Id n) (Literal number 0))])])))
   (LocalFunction
     (Binder inc)
     (Function
       [(ClvMarker)
        (ClvParam n false (ClvTypeName int53))
        (ClvParam flag true (ClvTypeName boolean))
        (ClvPre
          (BinOp and (BinOp gt (Id n) (Literal number 0)) (BinOp lt (Id n) (Literal number 10))))
        (ClvPost (BinOp eq (Id result) (BinOp add (Id n) (Literal number 1))))
        (ClvReturn nil (ClvTypeName int53))]
       [(Binder n) (Binder flag)]
       false
       (Block [(Return [(BinOp add (Id n) (Literal number 1))])])))
   (LocalFunction
     (Binder size)
     (Function
       [(ClvUnsafe)
        (ClvParam s false (ClvTypeName string))
        (ClvReturn size (ClvTypeName int53))
        (ClvReturn err (ClvTypeOptional (ClvTypeName string)))]
       [(Binder s)]
       false
       (Block [(Return [(UnOp len (Id s))])])))
   (ClvRegion
     [(Local
        [(Function
           [(ClvParam xs false (ClvTypeApply (ClvTypeName Seq) [(ClvTypeName int53)]))
            (ClvDecrease [(UnOp len (Id xs))])]
           [(Binder xs)]
           false
           (Block [(Return [(UnOp len (Id xs))])]))]
        [(Binder count)])])])
