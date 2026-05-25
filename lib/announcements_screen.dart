import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'constants.dart';
import 'api_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- DATA MODEL ---
class Announcement {
  final int id;
  final String title;
  final String body;
  final String priority; 
  final DateTime publishedOn;

  Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.priority,
    required this.publishedOn,
  });

  // 👇 ADDED: Factory to easily convert MySQL JSON into a Dart Object
  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: int.tryParse(json['id'].toString()) ?? 0,
      title: json['title'] ?? 'No Title',
      body: json['body'] ?? 'No content available.',
      priority: json['priority'] ?? 'normal',
      publishedOn: DateTime.tryParse(json['published_on'] ?? '') ?? DateTime.now(),
    );
  }

  bool get isNew => DateTime.now().difference(publishedOn).inDays <= 3;
  bool get isHighPriority => priority.toLowerCase() == 'high';
}

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Announcement> _allAnnouncements = [];
  List<Announcement> _filteredAnnouncements = [];
  
  // 👇 ADDED: State variables for network calls
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchAnnouncements(); // Fetch from database on load!
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 👇 ADDED: The real network fetch function
  Future<void> _fetchAnnouncements() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? companyId = prefs.getString('company_id');

      // Send the request as POST to send the company_id securely
      final response = await http.post(
        Uri.parse(ApiConstants.getAnnouncements),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          'company_id': companyId ?? '0', 
        },
      ).timeout(const Duration(seconds: 10));

      // 🛑 ALWAYS CHECK MOUNTED AFTER AWAIT
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          final List<dynamic> records = data['data'];
          setState(() {
            _allAnnouncements = records.map((json) => Announcement.fromJson(json)).toList();
            _filteredAnnouncements = List.from(_allAnnouncements);
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = data['message'] ?? 'Failed to load announcements';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Server error: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Network error. Please check your connection.';
        _isLoading = false;
      });
      debugPrint('Error fetching announcements: $e');
    }
  }

  void _filterNews(String query) {
    final lowerQuery = query.toLowerCase();
    setState(() {
      _filteredAnnouncements = _allAnnouncements.where((news) {
        return news.title.toLowerCase().contains(lowerQuery) || 
               news.body.toLowerCase().contains(lowerQuery);
      }).toList();
    });
  }

  void _openArticleModal(Announcement news) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (context) => _buildArticleReader(news),
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
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 5, offset: const Offset(0, 2))],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.arrow_back_rounded, size: 16, color: kTextDark),
                            const SizedBox(width: 8),
                            Text("Back", style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: kTextDark)),
                          ],
                        ),
                      ),
                    ),
                    
                    Text("Company News", style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w800, color: kTextDark, letterSpacing: -1)),
                    const SizedBox(height: 6),
                    Text("Stay updated with the latest team alerts.", style: GoogleFonts.inter(fontSize: 14, color: kTextMuted, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),

            // SEARCH BAR
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              sliver: SliverToBoxAdapter(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _filterNews,
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500, color: kTextDark),
                    decoration: InputDecoration(
                      hintText: "Search announcements...",
                      hintStyle: GoogleFonts.inter(color: kTextMuted),
                      prefixIcon: const Icon(Icons.search_rounded, color: kTextMuted, size: 20),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    ),
                  ),
                ),
              ),
            ),

            // 👇 ADDED: Dynamic Loading, Error, and Empty States
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: kPrimaryGreen)),
              )
            else if (_errorMessage != null)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.black26),
                      const SizedBox(height: 16),
                      Text(_errorMessage!, style: GoogleFonts.inter(color: kTextMuted)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchAnnouncements,
                        style: ElevatedButton.styleFrom(backgroundColor: kPrimaryGreen),
                        child: const Text("Try Again", style: TextStyle(color: Colors.white)),
                      )
                    ],
                  ),
                ),
              )
            else if (_filteredAnnouncements.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.folder_open_rounded, size: 60, color: Colors.black12),
                      const SizedBox(height: 16),
                      Text("No active announcements found.", style: GoogleFonts.inter(color: kTextMuted, fontSize: 16)),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 20.0),
                        child: _buildNewsCard(_filteredAnnouncements[index]),
                      );
                    },
                    childCount: _filteredAnnouncements.length,
                  ),
                ),
              ),
            
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildNewsCard(Announcement news) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: news.isHighPriority ? Colors.redAccent : kPrimaryGreen, width: 6)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      if (news.isNew) ...[
                        _buildBadge("NEW", const Color(0xFF00b894), const Color(0xFF00b894).withValues(alpha: 0.15)),
                        const SizedBox(width: 8),
                      ],
                      _buildBadge(
                        news.priority.toUpperCase(),
                        news.isHighPriority ? Colors.redAccent : kPrimaryGreen,
                        news.isHighPriority ? Colors.redAccent.withValues(alpha: 0.15) : kPrimaryGreen.withValues(alpha: 0.15),
                      ),
                    ],
                  ),
                  const Icon(Icons.campaign_rounded, color: Colors.black12, size: 24),
                ],
              ),
              const SizedBox(height: 16),

              Text(
                news.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: kTextDark, height: 1.3),
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  const Icon(Icons.access_time_rounded, size: 14, color: kTextMuted),
                  const SizedBox(width: 6),
                  Text(
                    DateFormat('MMM d, yyyy').format(news.publishedOn),
                    style: GoogleFonts.inter(fontSize: 12, color: kTextMuted, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Text(
                news.body.replaceAll('\n', ' '), 
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF555555), height: 1.5),
              ),
              const SizedBox(height: 20),

              InkWell(
                onTap: () => _openArticleModal(news),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Read Full Update", style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: kPrimaryGreen)),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_rounded, size: 14, color: kPrimaryGreen),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
      child: Text(
        text,
        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: textColor, letterSpacing: 0.5),
      ),
    );
  }

  Widget _buildArticleReader(Announcement news) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85, 
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(10))),
          
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildBadge(
                            news.priority.toUpperCase(),
                            news.isHighPriority ? Colors.redAccent : kPrimaryGreen,
                            news.isHighPriority ? Colors.redAccent.withValues(alpha: 0.15) : kPrimaryGreen.withValues(alpha: 0.15),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            DateFormat('MMM d, yyyy • h:mm a').format(news.publishedOn),
                            style: GoogleFonts.inter(fontSize: 12, color: kTextMuted, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        news.title,
                        style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: kTextDark, height: 1.2),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: kTextMuted),
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFFF4F6F9)),
                )
              ],
            ),
          ),
          
          const Divider(height: 1),
          
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: Text(
                news.body,
                style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF333333), height: 1.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}