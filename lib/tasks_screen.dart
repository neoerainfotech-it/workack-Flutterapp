import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import 'dart:convert';
import 'constants.dart';

// --- DATA MODEL ---
class EmployeeTask {
  final int id;
  final String title;
  final String project;
  final DateTime dueDate;
  bool isCompleted;

  EmployeeTask({
    required this.id,
    required this.title,
    required this.project,
    required this.dueDate,
    this.isCompleted = false,
  });

  Color get urgencyColor {
    if (isCompleted) return kPrimaryGreen;
    final daysDiff = dueDate.difference(DateTime.now()).inDays;
    if (daysDiff < 3) return Colors.redAccent;
    if (daysDiff < 7) return const Color(0xFFe17055); 
    return kPrimaryGreen;
  }

  // --- LOCAL STORAGE SYNC ---
  Map<String, dynamic> toJson() => {
    'id': id.toString(),
    'title': title,
    'project': project,
    'due_date': dueDate.toIso8601String(),
    'status': isCompleted ? "Completed" : "Pending",
  };

  factory EmployeeTask.fromJson(Map<String, dynamic> json) {
    return EmployeeTask(
      id: int.parse(json['id'].toString()),
      title: json['title'] ?? 'Untitled',
      project: json['project'] ?? 'Other',
      dueDate: json['due_date'] != null ? DateTime.parse(json['due_date']) : DateTime.now(),
      isCompleted: json['status'] == 'Completed' || json['status'] == '1',
    );
  }
}

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  // --- STATE ---
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _projectController = TextEditingController(); 
  DateTime? _selectedDueDate;
  String _currentFilter = 'all'; 
  bool _isFormExpanded = false;

  List<EmployeeTask> _tasks = [];

  @override
  void initState() {
    super.initState();
    _loadLocalTasks(); // Instantly loads from device memory
  }

  @override
  void dispose() {
    _titleController.dispose();
    _projectController.dispose(); 
    super.dispose();
  }

  // --- PURELY LOCAL LOGIC ---

  // Load from Device Storage
  Future<void> _loadLocalTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final String? tasksJson = prefs.getString('local_tasks');
    
    if (tasksJson != null) {
      final List<dynamic> decoded = json.decode(tasksJson);
      setState(() {
        _tasks = decoded.map((data) => EmployeeTask.fromJson(data)).toList();
      });
    }
  }

  // Save to Device Storage
  Future<void> _saveLocalTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = json.encode(_tasks.map((t) => t.toJson()).toList());
    await prefs.setString('local_tasks', encoded);
  }

  // --- ACTION LOGIC ---

  List<EmployeeTask> get _filteredTasks {
    if (_currentFilter == 'pending') return _tasks.where((t) => !t.isCompleted).toList();
    if (_currentFilter == 'completed') return _tasks.where((t) => t.isCompleted).toList();
    return _tasks;
  }

  int get _pendingCount => _tasks.where((t) => !t.isCompleted).length;
  int get _completedCount => _tasks.where((t) => t.isCompleted).length;

  Future<void> _pickDueDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDueDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(), 
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: kPrimaryGreen, onPrimary: Colors.white, onSurface: Colors.black),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _selectedDueDate = picked);
  }

  void _addTask() {
    if (_formKey.currentState!.validate() && _selectedDueDate != null) {
      final title = _titleController.text.trim();
      final project = _projectController.text.trim(); 

      // Create a unique ID using the current time
      int uniqueId = DateTime.now().millisecondsSinceEpoch; 
      
      final newTask = EmployeeTask(
        id: uniqueId, 
        title: title, 
        project: project, 
        dueDate: _selectedDueDate!
      );
      
      setState(() {
        _tasks.insert(0, newTask); // Adds to the top of the list instantly
        _titleController.clear();
        _projectController.clear(); 
        _selectedDueDate = null;
        _isFormExpanded = false;
      });
      
      _saveLocalTasks(); // Saves to the device silently
      _showSnackBar("Task added successfully!");

    } else if (_selectedDueDate == null) {
      _showSnackBar("Please select a due date.", isError: true);
    }
  }

  void _toggleTaskCompletion(EmployeeTask task) {
    setState(() => task.isCompleted = !task.isCompleted);
    _saveLocalTasks();
    _showSnackBar(task.isCompleted ? "Task completed." : "Task marked pending.");
  }

  void _deleteTask(EmployeeTask task) {
    setState(() => _tasks.removeWhere((t) => t.id == task.id));
    _saveLocalTasks();
    _showSnackBar("Task deleted.");
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        backgroundColor: isError ? Colors.redAccent : kPrimaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
        duration: const Duration(seconds: 2), // Faster snackbar for a faster app
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // --- HEADER ---
            SliverAppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              pinned: false,
              title: Text("Task Manager", style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, color: kTextDark, letterSpacing: -0.5)),
            ),

            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  
                 // --- STATS ROW ---
                 SizedBox(
                   height: 130, 
                   child: ListView(
                     scrollDirection: Axis.horizontal,
                     physics: const BouncingScrollPhysics(),
                     children: [
                       _buildStatCard("Total Tasks", "${_tasks.length}", const [Color(0xFFa18cd1), Color(0xFFfbc2eb)], Icons.format_list_bulleted_rounded),
                       const SizedBox(width: 16),
                       _buildStatCard("Pending", "$_pendingCount", const [Color(0xFFf6d365), Color(0xFFfda085)], Icons.access_time_rounded),
                       const SizedBox(width: 16),
                       _buildStatCard("Completed", "$_completedCount", const [Color(0xFF84fab0), Color(0xFF8fd3f4)], Icons.done_all_rounded),
                     ],
                   ),
                 ),
                 const SizedBox(height: 24),

                 // --- ADD TASK FORM ---
                 _buildAddTaskForm(),
                 const SizedBox(height: 32),

                 // --- FILTER BAR ---
                 Row(
                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                   children: [
                     Text("My To-Do List", style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: kTextDark)),
                     Container(
                       padding: const EdgeInsets.symmetric(horizontal: 12),
                       decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black.withValues(alpha: 0.05))),
                       child: DropdownButtonHideUnderline(
                         child: DropdownButton<String>(
                           value: _currentFilter,
                           icon: const Icon(Icons.filter_list_rounded, size: 16, color: kTextMuted),
                           style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: kTextDark),
                           items: const [
                             DropdownMenuItem(value: 'all', child: Text("All Tasks")),
                             DropdownMenuItem(value: 'pending', child: Text("Pending")),
                             DropdownMenuItem(value: 'completed', child: Text("Completed")),
                           ],
                           onChanged: (val) => setState(() => _currentFilter = val!),
                         ),
                       ),
                     ),
                   ],
                 ),
                 const SizedBox(height: 16),
                ]),
              ),
            ),

            // --- TASK LIST ---
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              sliver: _filteredTasks.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40.0),
                      child: Center(
                        child: Column(
                          children: [
                            const Icon(Icons.task_alt_rounded, size: 60, color: Colors.black12),
                            const SizedBox(height: 16),
                            Text("No tasks found.", style: GoogleFonts.inter(color: kTextMuted, fontSize: 16)),
                          ],
                        ),
                      ),
                    ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        return _buildTaskCard(_filteredTasks[index]);
                      },
                      childCount: _filteredTasks.length,
                    ),
                  ),
            ),
            
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // WIDGET BUILDERS
  // =========================================================================

  Widget _buildStatCard(String title, String value, List<Color> gradient, IconData icon) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const Spacer(),
          Text(value, style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: kTextDark)),
          Text(title, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: kTextMuted)),
        ],
      ),
    );
  }

  Widget _buildAddTaskForm() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 10))],
          ),
          child: Column(
            children: [
              GestureDetector(
                onTap: () => setState(() => _isFormExpanded = !_isFormExpanded),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: kPrimaryGreen.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.add_task_rounded, color: kPrimaryGreen, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text("Add New Task", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: kTextDark)),
                    const Spacer(),
                    Icon(_isFormExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: kTextMuted),
                  ],
                ),
              ),
              
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 300),
                crossFadeState: _isFormExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                firstChild: const SizedBox(width: double.infinity, height: 0),
                secondChild: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(padding: EdgeInsets.symmetric(vertical: 16.0), child: Divider(height: 1)),
                      
                      _buildInputLabel("Task Title"),
                      TextFormField(
                        controller: _titleController,
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
                        decoration: _inputDecoration("e.g. Prepare monthly report"),
                        validator: (v) => v!.trim().isEmpty ? "Required" : null,
                      ),
                      const SizedBox(height: 16),

                      LayoutBuilder(builder: (context, constraints) {
                        return Flex(
                          direction: constraints.maxWidth > 600 ? Axis.horizontal : Axis.vertical,
                          children: [
                            Expanded(
                              flex: constraints.maxWidth > 600 ? 1 : 0,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildInputLabel("Project Category"),
                                  TextFormField(
                                    controller: _projectController,
                                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
                                    decoration: _inputDecoration("e.g. Frontend Dev"),
                                    validator: (v) => v!.trim().isEmpty ? "Required" : null,
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: constraints.maxWidth > 600 ? 0 : 16, width: constraints.maxWidth > 600 ? 16 : 0),
                            Expanded(
                              flex: constraints.maxWidth > 600 ? 1 : 0,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildInputLabel("Due Date"),
                                  GestureDetector(
                                    onTap: _pickDueDate,
                                    child: AbsorbPointer(
                                      child: TextFormField(
                                        key: ValueKey(_selectedDueDate),
                                        initialValue: _selectedDueDate != null ? DateFormat('MMM dd, yyyy').format(_selectedDueDate!) : "",
                                        style: GoogleFonts.inter(fontSize: 14, color: kTextDark, fontWeight: FontWeight.w500),
                                        decoration: _inputDecoration("Select Date").copyWith(prefixIcon: const Icon(Icons.calendar_today_rounded, size: 18, color: kPrimaryGreen)),
                                        validator: (_) => _selectedDueDate == null ? "Required" : null,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }),
                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _addTask,
                          icon: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                          label: Text("Create Task", style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white)),
                          style: ElevatedButton.styleFrom(backgroundColor: kPrimaryGreen, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(text.toUpperCase(), style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: kTextMuted, letterSpacing: 0.5)),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: Colors.black.withValues(alpha: 0.2)),
      filled: true,
      fillColor: const Color(0xFFF4F6F9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kPrimaryGreen, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5))),
    );
  }

  Widget _buildTaskCard(EmployeeTask task) {
    return Dismissible(
      key: Key(task.id.toString()),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _deleteTask(task),
      background: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(20)),
        alignment: Alignment.centerRight,
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 28),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black.withValues(alpha: 0.03)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => _toggleTaskCompletion(task),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: task.isCompleted ? kPrimaryGreen : Colors.transparent,
                  border: Border.all(color: task.isCompleted ? kPrimaryGreen : kTextMuted.withValues(alpha: 0.5), width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: task.isCompleted ? const Icon(Icons.check_rounded, size: 18, color: Colors.white) : null,
              ),
            ),
            const SizedBox(width: 16),
            
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: GoogleFonts.inter(
                      fontSize: 16, 
                      fontWeight: FontWeight.w700, 
                      color: task.isCompleted ? kTextMuted : kTextDark,
                      decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(6)),
                        child: Text(task.project, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: kTextMuted)),
                      ),
                      const Spacer(),
                      Icon(Icons.calendar_today_rounded, size: 12, color: task.urgencyColor),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('MMM dd').format(task.dueDate),
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: task.urgencyColor),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}