import 'package:flutter/material.dart' as material;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speak_dine/view/authScreens/login_view.dart';
import 'package:speak_dine/view/user/restaurant_detail.dart';
import 'package:speak_dine/services/speech_service.dart';
import 'package:speak_dine/services/intent_service.dart';
import 'package:speak_dine/widgets/notification_bell.dart';

class UserHomeView extends material.StatefulWidget {
  final VoidCallback? onCartChanged;
  final VoidCallback? onViewCart;
  final VoidCallback? onViewPayments;

  const UserHomeView({
    super.key,
    this.onCartChanged,
    this.onViewCart,
    this.onViewPayments,
  });

  @override
  material.State<UserHomeView> createState() => _UserHomeViewState();
}

class _UserHomeViewState extends material.State<UserHomeView> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String userName = "Customer";

  final SpeechService speechService = SpeechService();
  final IntentService intentService = IntentService();

  bool _isListening = false;
  String _recognizedText = "";

  @override
  void initState() {
    super.initState();
    _loadUserData();
    speechService.init();
  }

  @override
  void dispose() {
    speechService.dispose();
    super.dispose();
  }
  
  Future<void> _handleVoiceCommand(String text) async {
    setState(() {
      _recognizedText = text;
      _isListening = false;
    });

    final intent = intentService.detectIntent(text);
    bool stayedOnScreen = true;

    switch (intent.action) {
      case "OPEN_RESTAURANT":
        await _openRestaurantByName(intent.restaurantName);
        stayedOnScreen = false;
        break;
      case "SHOW_CART":
        await speechService.speak("Opening cart");
        widget.onViewCart?.call();
        stayedOnScreen = false;
        break;
      case "PLACE_ORDER":
        await speechService.speak("Opening cart");
        widget.onViewCart?.call();
        stayedOnScreen = false;
        break;
      case "SHOW_MENU":
        await speechService.speak("Showing restaurants");
        break;
      case "MAKE_PAYMENT":
        await speechService.speak("Opening payments");
        widget.onViewPayments?.call();
        stayedOnScreen = false;
        break;
      default:
        await speechService.speak("Sorry, I did not understand");
    }

    if (stayedOnScreen && mounted) _restartListeningAfterDelay();
  }

  void _restartListeningAfterDelay() {
    Future.delayed(const Duration(milliseconds: 2200), () async {
      if (!mounted) return;
      final started = await speechService.startListening(
        onResultText: (text, isFinal) {
          if (isFinal && text.trim().isNotEmpty) {
            _handleVoiceCommand(text);
          } else {
            setState(() => _recognizedText = text);
          }
        },
      );
      if (started && mounted) setState(() => _isListening = true);
    });
  }

  Future<void> _openRestaurantByName(String? name) async {
    if (name == null || name.isEmpty) {
      await speechService.speak("Which restaurant? Say for example, open K F C");
      return;
    }
    final snapshot = await _firestore.collection('restaurants').get();
    if (!mounted) return;
    final docs = snapshot.docs;
    final search = name.toLowerCase().replaceAll(' ', '');
    QueryDocumentSnapshot<Map<String, dynamic>>? match;
    for (final doc in docs) {
      final data = doc.data();
      final rName = (data['restaurantName'] as String? ?? '').toLowerCase().replaceAll(' ', '');
      if (rName.contains(search) || search.contains(rName)) {
        match = doc;
        break;
      }
    }
    if (match == null) {
      await speechService.speak("Restaurant not found. Say open and then the restaurant name.");
      return;
    }
    final data = match.data();
    final restaurantName = data['restaurantName'] as String? ?? 'Restaurant';
    await speechService.speak("Opening $restaurantName");
    material.Navigator.push(
      context,
      material.MaterialPageRoute(
        builder: (_) => RestaurantDetailView(
          restaurantId: match!.id,
          restaurantName: restaurantName,
          onCartChanged: widget.onCartChanged,
          onViewCart: widget.onViewCart,
          onViewPayments: widget.onViewPayments,
        ),
      ),
    );
  }
  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc =
          await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        setState(() {
          userName = doc.data()?['name'] ?? "Customer";
        });
      }
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;

    material.Navigator.pushAndRemoveUntil(
      context,
      material.MaterialPageRoute(builder: (_) => const LoginView()),
      (route) => false,
    );
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = material.Theme.of(context);

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [

        /// HEADER
        material.Padding(
          padding: const material.EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: material.Row(
            children: [
              material.Expanded(
                child: material.Column(
                  crossAxisAlignment:
                      material.CrossAxisAlignment.start,
                  children: [
                    Text("Hello, $userName").h4().semiBold(),
                    const Text("What would you like to eat?")
                        .muted()
                        .small(),
                  ],
                ),
              ),
              const NotificationBell(),
              const material.SizedBox(width: 8),
              GhostButton(
                density: ButtonDensity.icon,
                onPressed: _logout,
                child: material.Icon(
                  RadixIcons.exit,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),

        const material.SizedBox(height: 20),

        /// MIC SECTION
        material.Padding(
          padding: const material.EdgeInsets.symmetric(horizontal: 20),
          child: material.Row(
            children: [
              material.IconButton(
                icon:                     material.Icon(
                      _isListening
                          ? material.Icons.mic
                          : material.Icons.mic_none,
                ),
                onPressed: () async {
                  if (_isListening) {
                    await speechService.stopListening();
                    setState(() => _isListening = false);
                  } else {
                    final started =
                        await speechService.startListening(
                      onResultText: (text, isFinal) {
                        if (isFinal && text.trim().isNotEmpty) {
                          _handleVoiceCommand(text);
                        } else {
                          setState(() => _recognizedText = text);
                        }
                      },
                    );

                    if (started) setState(() => _isListening = true);
                  }
                },
              ),
              const material.SizedBox(width: 12),
              material.Expanded(
                child: material.Text(
                  _recognizedText.isEmpty
                      ? (_isListening ? "Listening... say e.g. show cart, open KFC" : "Tap mic and speak...")
                      : "You said: $_recognizedText",
                ),
              ),
            ],
          ),
        ),

        const material.SizedBox(height: 20),

        /// TITLE
        const material.Padding(
          padding:
              material.EdgeInsets.symmetric(horizontal: 20),
          child: material.Text(
            "Restaurants Near You",
            style: material.TextStyle(
              fontWeight: material.FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),

        const material.SizedBox(height: 12),

        /// RESTAURANT LIST
        material.Expanded(
          child: material.StreamBuilder<QuerySnapshot>(
            stream:
                _firestore.collection('restaurants').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState ==
                  material.ConnectionState.waiting) {
                return const material.Center(
                  child: material.CircularProgressIndicator(),
                );
              }

              if (!snapshot.hasData ||
                  snapshot.data!.docs.isEmpty) {
                return const material.Center(
                  child: material.Text(
                      "No restaurants available"),
                );
              }

              final restaurants = snapshot.data!.docs;

              return material.ListView.builder(
                padding:
                    const material.EdgeInsets.symmetric(
                        horizontal: 20),
                itemCount: restaurants.length,
                itemBuilder: (context, index) {
                  final data =
                      restaurants[index].data()
                          as Map<String, dynamic>;
                  final restaurantId =
                      restaurants[index].id;

                  return material.Padding(
                    padding: const material.EdgeInsets.only(
                        bottom: 12),
                    child: material.Card(
                      child: material.ListTile(
                        title: material.Text(
                          data['restaurantName'] ??
                              "Restaurant",
                          style: const material.TextStyle(
                              fontWeight:
                                  material.FontWeight.bold),
                        ),
                        onTap: () {
                          material.Navigator.push(
                            context,
                            material.MaterialPageRoute(
                              builder: (_) =>
                                  RestaurantDetailView(
                                restaurantId: restaurantId,
                                restaurantName:
                                    data['restaurantName'] ??
                                        "",
                                onCartChanged:
                                    widget.onCartChanged,
                                onViewCart:
                                    widget.onViewCart,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}