import { expect, mock, test } from "bun:test";
mock.module("gpui-kit",()=>({View:class {},div(){},svg(){},image(){}}));
mock.module("gpui-base",()=>({h_flex(){},v_flex(){}}));
mock.module("herdr",()=>({spaces(){},panes(){},run(){},theme(){},openOverlay(){},window(){},nextCommand(){},exec(){},notify(){},shared(){},setShared(){},agents(){},machines(){},hc(){},home(){},props(){},setAgentOrder(){}}));
const { clickSelection, moveTabOrder, dropTabOrder }=await import("../dotfiles/herdr-app/compact-terminals-bar/main.js");
test("shift click selects the anchored range in either direction; plain click clears the group",()=>{
 const ids=["a","b","c","d"];
 expect(clickSelection(ids,"b","d",true)).toEqual({anchor:"b",selected:["b","c","d"]});
 expect(clickSelection(ids,"d","b",true)).toEqual({anchor:"d",selected:["b","c","d"]});
 expect(clickSelection(ids,"b","d",false)).toEqual({anchor:"d",selected:[]});
 expect(clickSelection(ids,"gone","c",true)).toEqual({anchor:"c",selected:["c"]});
});
test("group moves preserve order and respect both boundaries",()=>{
 const ids=["a","b","c","d","e"];
 expect(moveTabOrder(ids,["b","c"],-1)).toEqual(["b","c","a","d","e"]);
 expect(moveTabOrder(ids,["b","c"],1)).toEqual(["a","d","b","c","e"]);
 expect(moveTabOrder(ids,["a","b"],-1)).toEqual(ids);
 expect(moveTabOrder(ids,["d","e"],1)).toEqual(ids);
 expect(moveTabOrder(ids,["gone"],1)).toEqual(ids);
 expect(ids).toEqual(["a","b","c","d","e"]);
});

test("dropping a selected group keeps its order on either side of the target",()=>{
 const ids=["a","b","c","d","e"];
 expect(dropTabOrder(ids,["b","c"],"e")).toEqual(["a","d","e","b","c"]);
 expect(dropTabOrder(ids,["c","d"],"a")).toEqual(["c","d","a","b","e"]);
 expect(dropTabOrder(ids,["b","c"],"c")).toEqual(ids);
 expect(dropTabOrder(ids,["gone"],"a")).toEqual(ids);
});
