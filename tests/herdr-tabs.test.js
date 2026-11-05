import { expect, mock, test } from "bun:test";
mock.module("gpui-kit",()=>({View:class {},div(){},svg(){},image(){}}));
mock.module("gpui-base",()=>({h_flex(){},v_flex(){}}));
mock.module("herdr",()=>({spaces(){},panes(){},run(){},theme(){},openOverlay(){},window(){},nextCommand(){},exec(){},notify(){},hc(){},shared(){},setShared(){},agents(){},machines(){},hc(){},home(){},props(){},setAgentOrder(){}}));
const { previewPosition, clickSelection, moveTabOrder, dropTabOrder, insertionSlot, insertTabOrder }=await import("../dotfiles/herdr-app/compact-terminals-bar/main.js");
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

test("the insertion slot stays put while hovering its gap, then crosses a neighbor midpoint",()=>{
 expect(insertionSlot([100,100,100],100,0,1,150)).toBe(1);
 expect(insertionSlot([100,100,100],100,0,1,260)).toBe(2);
 expect(insertionSlot([100,100,100],100,0,2,260)).toBe(2);
 expect(insertionSlot([100,100,100],100,0,1,40)).toBe(0);
 expect(insertTabOrder(["a","b","c","d"],["b","c"],2)).toEqual(["a","d","b","c"]);
});

test("drag preview is centered on the pointer and stays inside its panel",()=>{
 expect(previewPosition({x:200,y:100},{width:500,height:300})).toEqual({x:120,y:83});
 expect(previewPosition({x:2,y:2},{width:500,height:300})).toEqual({x:8,y:8});
 expect(previewPosition({x:499,y:299},{width:500,height:300})).toEqual({x:332,y:258});
});
test("hovering each half inserts before or after the row, including skipping rows",()=>{
 expect(insertionSlot([30,30,30],30,0,3,41)).toBe(1);
 expect(insertionSlot([30,30,30],30,0,3,49)).toBe(2);
 expect(insertionSlot([30,30,30],30,0,0,71)).toBe(1);
 expect(insertionSlot([30,30,30],30,0,0,79)).toBe(2);
});
