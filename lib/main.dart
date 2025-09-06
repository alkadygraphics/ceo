import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class Customer {
  String id, name; String? email, phone, address, seller;
  double expectedRevenue; Contract? contract; RiskFlags risk;
  Customer({required this.id, required this.name, this.email, this.phone, this.address, this.seller,
    this.expectedRevenue=0, this.contract, RiskFlags? risk}) : risk = risk ?? RiskFlags();
  Map<String,dynamic> toJson()=>{'id':id,'name':name,'email':email,'phone':phone,'address':address,'seller':seller,
    'expectedRevenue':expectedRevenue,'contract':contract?.toJson(),'risk':risk.toJson()};
  factory Customer.fromJson(Map<String,dynamic> j)=>Customer(
    id:j['id'], name:j['name'], email:j['email'], phone:j['phone'], address:j['address'], seller:j['seller'],
    expectedRevenue:(j['expectedRevenue']??0).toDouble(),
    contract:j['contract']!=null?Contract.fromJson(j['contract']):null,
    risk:j['risk']!=null?RiskFlags.fromJson(j['risk']):RiskFlags());
}
class Contract {
  DateTime startDate, dueDate; int durationDays; String status; String? notes;
  Contract({DateTime? startDate,this.durationDays=15,DateTime? dueDate,this.status='open',this.notes})
    : startDate=startDate??DateTime.now(),
      dueDate=dueDate??(startDate??DateTime.now()).add(Duration(days:durationDays));
  Map<String,dynamic> toJson()=>{'startDate':startDate.toIso8601String(),'durationDays':durationDays,
    'dueDate':dueDate.toIso8601String(),'status':status,'notes':notes};
  factory Contract.fromJson(Map<String,dynamic> j)=>Contract(
    startDate:DateTime.parse(j['startDate']), durationDays:j['durationDays'],
    dueDate:DateTime.parse(j['dueDate']), status:j['status'], notes:j['notes']);
}
class RiskFlags {
  bool trouble,paymentIssue,docsMissing,vip,legal;
  RiskFlags({this.trouble=false,this.paymentIssue=false,this.docsMissing=false,this.vip=false,this.legal=false});
  Map<String,dynamic> toJson()=>{'trouble':trouble,'paymentIssue':paymentIssue,'docsMissing':docsMissing,'vip':vip,'legal':legal};
  factory RiskFlags.fromJson(Map<String,dynamic> j)=>RiskFlags(
    trouble:j['trouble']??false,paymentIssue:j['paymentIssue']??false,docsMissing:j['docsMissing']??false,
    vip:j['vip']??false,legal:j['legal']??false);
}
class Repo {
  static const _k='customers_v1';
  static Future<List<Customer>> load() async {
    final p=await SharedPreferences.getInstance(); final raw=p.getString(_k); if(raw==null) return [];
    final l=(jsonDecode(raw) as List).cast<Map<String,dynamic>>(); return l.map((j)=>Customer.fromJson(j)).toList();
  }
  static Future<void> save(List<Customer> cs) async {
    final p=await SharedPreferences.getInstance();
    await p.setString(_k, jsonEncode(cs.map((e)=>e.toJson()).toList(growable:false)));
  }
}
int calcPriorityScore(Customer c){
  final now=DateTime.now(); int base=10, add=0;
  if(c.contract!=null && c.contract!.status=='open'){
    final due=c.contract!.dueDate;
    final daysLeft=due.difference(DateTime(now.year,now.month,now.day)).inDays;
    if(daysLeft>=15) base=10; else if(daysLeft>=7) base=30; else if(daysLeft>=3) base=60; else if(daysLeft>=1) base=80;
    else { final overdue=DateTime(now.year,now.month,now.day).difference(due).inDays; base=90+(overdue*2).clamp(0,10); }
  }
  if(c.risk.trouble) add+=20; if(c.risk.paymentIssue) add+=15; if(c.risk.docsMissing) add+=10; if(c.risk.legal) add+=25;
  if(c.expectedRevenue>=30000) add+=10; else if(c.expectedRevenue>=10000) add+=5;
  var s=base+add; if(c.risk.vip && s<70) s=70; return s.clamp(0,100);
}
String badgeFor(Customer c){
  final s=calcPriorityScore(c); final now=DateTime.now(); final due=c.contract?.dueDate;
  final daysLeft=due==null?9999:due.difference(DateTime(now.year,now.month,now.day)).inDays;
  if(c.risk.legal || c.risk.trouble || s>=85 || daysLeft<0) return 'RISK'; if(s>=75 || daysLeft<=2) return 'AT RISK'; return 'OK';
}

void main()=>runApp(const AlkadyApp());
class AlkadyApp extends StatelessWidget{ const AlkadyApp({super.key});
  @override Widget build(BuildContext context)=>MaterialApp(debugShowCheckedModeBanner:false,title:'Alkady Prioritizer',
    theme:ThemeData(colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF0D2740)),useMaterial3:true),
    home:const HomePage());}

class HomePage extends StatefulWidget{ const HomePage({super.key}); @override State<HomePage> createState()=>_HomePageState();}
class _HomePageState extends State<HomePage>{
  List<Customer> customers=[]; String q='';
  @override void initState(){ super.initState(); _load(); }
  Future<void> _load() async{ customers=await Repo.load(); setState((){}); }
  Future<void> _save() async{ await Repo.save(customers); }
  @override Widget build(BuildContext context){
    final f=customers.where((c)=>c.name.toLowerCase().contains(q.toLowerCase())).toList()
      ..sort((a,b)=>calcPriorityScore(b).compareTo(calcPriorityScore(a)));
    final high=f.where((c)=>calcPriorityScore(c)>=85).length;
    final overdue=f.where((c)=>(c.contract?.dueDate??DateTime(2100)).isBefore(DateTime.now()) && (c.contract?.status=='open')).length;
    final eligible=f.where((c)=>(c.contract?.status=='open')).length;
    return Scaffold(appBar:AppBar(title:const Text('Delivery Prioritizer')), body:Column(children:[
      Padding(padding:const EdgeInsets.all(12), child:Row(mainAxisAlignment:MainAxisAlignment.spaceAround, children:[
        _kpi('Total', f.length.toString()), _kpi('Eligible', eligible.toString()),
        _kpi('High Score', high.toString()), _kpi('Overdue', overdue.toString()),
      ])),
      Padding(padding:const EdgeInsets.symmetric(horizontal:12),
        child:TextField(decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Search by name'),
          onChanged:(v)=>setState(()=>q=v))),
      const SizedBox(height:6),
      Expanded(child:ListView.builder(itemCount:f.length,itemBuilder:(context,i){
        final c=f[i]; final s=calcPriorityScore(c); final due=c.contract?.dueDate;
        final dueTxt=due==null?'-':DateFormat('dd MMM yyyy').format(due);
        return ListTile(title:Text(c.name,style:const TextStyle(fontWeight:FontWeight.w600)),
          subtitle:Text('Due: $dueTxt   Revenue: \$${c.expectedRevenue.toStringAsFixed(0)}'),
          trailing:Column(crossAxisAlignment:CrossAxisAlignment.end,mainAxisAlignment:MainAxisAlignment.center,children:[
            _scoreChip(s), const SizedBox(height:6), _badge(badgeFor(c))]),
          onTap:() async { await Navigator.push(context,MaterialPageRoute(builder:(_)=>DetailPage(customer:c))); await _save(); setState((){}); },);
      })),]),
      floatingActionButton:FloatingActionButton.extended(onPressed:() async {
        final c=await Navigator.push<Customer?>(context,MaterialPageRoute(builder:(_)=>const RegisterPage()));
        if(c!=null){ customers.add(c); await _save(); setState((){}); }},
        label:const Text('Add Customer'), icon:const Icon(Icons.person_add_alt_1)),);
  }
  Widget _kpi(String t,String v)=>Column(children:[
    Text(t,style:const TextStyle(fontSize:12,color:Colors.black54)),
    Text(v,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
  ]);
  Widget _scoreChip(int s){ Color bg=Colors.blue.shade100, fg=Colors.blue.shade900;
    if(s>=85){bg=Colors.red.shade100; fg=Colors.red.shade800;}
    else if(s>=75){bg=Colors.orange.shade100; fg=Colors.orange.shade800;}
    return Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
      decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(12)),
      child:Text('Score $s',style:TextStyle(color:fg,fontWeight:FontWeight.w700))); }
  Widget _badge(String b){ Color bg=Colors.green.shade100, fg=Colors.green.shade800;
    if(b=='RISK'){bg=Colors.red.shade100; fg=Colors.red.shade800;} else if(b=='AT RISK'){bg=Colors.orange.shade100; fg=Colors.orange.shade800;}
    return Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
      decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(10)),
      child:Text(b,style:TextStyle(color:fg,fontWeight:FontWeight.w700))); }
}

class RegisterPage extends StatefulWidget{ const RegisterPage({super.key}); @override State<RegisterPage> createState()=>_RegisterPageState();}
class _RegisterPageState extends State<RegisterPage>{
  final _f=GlobalKey<FormState>(); final name=TextEditingController(), email=TextEditingController(),
    phone=TextEditingController(), address=TextEditingController(), seller=TextEditingController(), revenue=TextEditingController();
  @override Widget build(BuildContext context){
    return Scaffold(appBar:AppBar(title:const Text('Register Customer')), body:Padding(padding:const EdgeInsets.all(16),
      child:Form(key:_f, child:ListView(children:[
        _fi('Name', name, req:true), _fi('Email', email), _fi('Phone', phone, kb:TextInputType.phone),
        _fi('Address', address), _fi('Seller', seller), _fi('Expected Revenue', revenue, kb:TextInputType.number),
        const SizedBox(height:16),
        ElevatedButton(onPressed:(){ if(_f.currentState!.validate()){
          final c=Customer(id:UniqueKey().toString(), name:name.text.trim(),
            email:email.text.trim().isEmpty?null:email.text.trim(),
            phone:phone.text.trim().isEmpty?null:phone.text.trim(),
            address:address.text.trim().isEmpty?null:address.text.trim(),
            seller:seller.text.trim().isEmpty?null:seller.text.trim(),
            expectedRevenue:double.tryParse(revenue.text.trim())??0,
            contract:Contract(), risk:RiskFlags());
          Navigator.pop(context,c);} }, child:const Text('SAVE')),
      ])),));}
  Widget _fi(String label, TextEditingController c,{bool req=false, TextInputType? kb}){
    return Padding(padding:const EdgeInsets.only(bottom:12),
      child:TextFormField(controller:c, keyboardType:kb,
        validator:(v)=> (req && (v==null || v.trim().isEmpty)) ? 'Required' : null,
        decoration:InputDecoration(labelText:label,border:const UnderlineInputBorder()),));}
}

class DetailPage extends StatefulWidget{ final Customer customer; const DetailPage({super.key, required this.customer});
  @override State<DetailPage> createState()=>_DetailPageState();}
class _DetailPageState extends State<DetailPage>{
  @override Widget build(BuildContext context){
    final c=widget.customer; final df=DateFormat('dd MMM yyyy'); final s=calcPriorityScore(c);
    return Scaffold(appBar:AppBar(title:Text(c.name)), body:ListView(padding:const EdgeInsets.all(16), children:[
      Row(children:[_badge(badgeFor(c)), const SizedBox(width:8), _scoreChip(s)]), const SizedBox(height:12),
      _kv('Phone', c.phone??'-'), _kv('Email', c.email??'-'), _kv('Address', c.address??'-'),
      _kv('Salesperson', c.seller??'-'), _kv('Revenue', '\$${c.expectedRevenue.toStringAsFixed(0)}'),
      const Divider(),
      ListTile(title:const Text('Contract'), subtitle:Text(c.contract==null?'None':
        'Due: ${df.format(c.contract!.dueDate)}  •  Status: ${c.contract!.status}'),
        trailing:TextButton(onPressed:()=>_editContract(context), child:const Text('Edit')),),
      const Divider(),
      const Text('Risk Flags', style:TextStyle(fontWeight: FontWeight.bold)),
      SwitchListTile(value:c.risk.trouble, onChanged:(v)=>setState(()=>c.risk.trouble=v), title:const Text('Trouble Maker')),
      SwitchListTile(value:c.risk.paymentIssue, onChanged:(v)=>setState(()=>c.risk.paymentIssue=v), title:const Text('Payment Issue')),
      SwitchListTile(value:c.risk.docsMissing, onChanged:(v)=>setState(()=>c.risk.docsMissing=v), title:const Text('Docs Missing')),
      SwitchListTile(value:c.risk.vip, onChanged:(v)=>setState(()=>c.risk.vip=v), title:const Text('VIP (fast track)')),
      SwitchListTile(value:c.risk.legal, onChanged:(v)=>setState(()=>c.risk.legal=v), title:const Text('Legal Action')),
      const SizedBox(height:12),
      ElevatedButton(onPressed:(){ setState(()=>c.contract?.status='closed'); }, child:const Text('Mark as Completed')),
    ]));}
  Widget _kv(String k,String v)=>Padding(padding:const EdgeInsets.symmetric(vertical:4),
    child:Row(children:[SizedBox(width:120, child:Text(k.toUpperCase(),style:const TextStyle(color:Colors.black54,fontSize:12))),
      Expanded(child:Text(v,style:const TextStyle(fontSize:16)))]));
  Widget _badge(String b){ Color bg=Colors.green.shade100, fg=Colors.green.shade800;
    if(b=='RISK'){bg=Colors.red.shade100; fg=Colors.red.shade800;} else if(b=='AT RISK'){bg=Colors.orange.shade100; fg=Colors.orange.shade800;}
    return Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
      decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(10)), child:Text(b,style:TextStyle(color:fg,fontWeight:FontWeight.w700))); }
  Widget _scoreChip(int s){ Color bg=Colors.blue.shade100, fg=Colors.blue.shade900;
    if(s>=85){bg=Colors.red.shade100; fg=Colors.red.shade800;} else if(s>=75){bg=Colors.orange.shade100; fg=Colors.orange.shade800;}
    return Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
      decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(12)),
      child:Text('Score $s',style:TextStyle(color:fg,fontWeight:FontWeight.w700))); }
  Future<void> _editContract(BuildContext context) async {
    final c=widget.customer; final duration=TextEditingController(text:c.contract?.durationDays.toString()??'15');
    DateTime due=c.contract?.dueDate ?? DateTime.now().add(const Duration(days:15));
    String status=c.contract?.status ?? 'open';
    await showModalBottomSheet(context:context,isScrollControlled:true,builder:(ctx){
      return Padding(padding:EdgeInsets.only(bottom:MediaQuery.of(ctx).viewInsets.bottom),
        child:StatefulBuilder(builder:(ctx,setS){ return Padding(padding:const EdgeInsets.all(16), child:Column(mainAxisSize:MainAxisSize.min, children:[
          const Text('Edit Contract', style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)),
          TextField(controller:duration, keyboardType:TextInputType.number, decoration:const InputDecoration(labelText:'Duration (days)'),
            onChanged:(_){ final d=int.tryParse(duration.text.trim())??15; setS(()=> due=DateTime.now().add(Duration(days:d))); }),
          const SizedBox(height:8),
          Row(children:[const Text('Due Date: '), Text(DateFormat('dd MMM yyyy').format(due), style:const TextStyle(fontWeight:FontWeight.w600))]),
          const SizedBox(height:8),
          DropdownButtonFormField<String>(value:status, items:const[
            DropdownMenuItem(value:'open', child:Text('open')), DropdownMenuItem(value:'closed', child:Text('closed')),
          ], onChanged:(v)=>setS(()=>status=v??'open'), decoration:const InputDecoration(labelText:'Status')),
          const SizedBox(height:12),
          ElevatedButton(onPressed:(){ final d=int.tryParse(duration.text.trim())??15;
            c.contract=Contract(startDate:DateTime.now(), durationDays:d, dueDate:due, status:status);
            Navigator.pop(ctx); (this as State).setState((){}); }, child:const Text('Save')),
        ])); })); });
  }
}
