// practice only: reads maestro hierarchy JSON on stdin, prints numbers only: the bounds of the elements whose text is
// exactly the login button word, and the screen size (the root bounds). No other text is printed.
let s='';process.stdin.on('data',(c)=>(s+=c)).on('end',()=>{let j;try{j=JSON.parse(s.slice(s.indexOf('{')));}catch(e){console.log('bounds=unreadable');return;}
const W='ログイン';const hit=[];let root='';
const walk=(n,dep)=>{const a=n.attributes||{};if(dep===0)root=a.bounds||'';if(a.text===W||a.accessibilityText===W)hit.push((a.bounds||'?')+(a.enabled==='false'?'disabled':''));(n.children||[]).forEach((c)=>walk(c,dep+1));};
walk(j,0);const nums=(b)=>String(b).replace(/[^0-9,[]a-z]/g,'');
console.log('login-button-bounds='+(hit.length?hit.map(nums).join(';'):'none')+' screen='+nums(root));});
