(Block
  [(ClvRegion
     [(Local [(Literal number 0x10 :type int53)] [(Binder n$1 :type int53)])
      (Local
        [(BinOp and
           (BinOp lt (Id n$1 :type int53) (Literal number 2 :type int53) :type boolean)
           (UnOp not
             (Paren
               (BinOp eq (Id n$1 :type int53) (Literal number 3 :type int53) :type boolean)
               :type boolean)
             :type boolean)
           :type boolean)]
        [(Binder b$2 :type boolean)])
      (Local
        [(BinOp add
           (UnOp unm
             (Paren
               (BinOp mul (Id n$1 :type int53) (Literal number 2 :type int53) :type int53)
               :type int53)
             :type int53)
           (Literal number 9007199254740992 :type int53)
           :type int53)]
        [(Binder m$3 :type int53)])
      (Local
        [(BinOp eq (Id b$2 :type boolean) (Literal true true :type boolean) :type boolean)
         (BinOp ne (Id m$3 :type int53) (Literal number 0 :type int53) :type boolean)]
        [(Binder c$4 :type boolean) (Binder d$5 :type boolean)])
      (Set
        [(Id c$4 :type boolean) (Id n$1 :type int53)]
        [(Id d$5 :type boolean)
         (BinOp sub (Id n$1 :type int53) (Literal number 1 :type int53) :type int53)])
      (If
        [(IfArm
           (Id c$4 :type boolean)
           (Block [(Call (Id assert) nil [(Id c$4 :type boolean) (Literal string "message")])]))]
        (Block [(Call (Id error) nil [(Literal string "unreachable") (Literal number 2)])]))])])
