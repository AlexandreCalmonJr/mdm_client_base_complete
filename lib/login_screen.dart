import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mdm_client_base/main.dart';
import 'package:provider/provider.dart';

class ImprovedLoginScreen extends StatefulWidget {
  const ImprovedLoginScreen({super.key});

  @override
  State<ImprovedLoginScreen> createState() => _ImprovedLoginScreenState();
}

class _ImprovedLoginScreenState extends State<ImprovedLoginScreen>
    with TickerProviderStateMixin {
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  String? _errorMessage;

  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late AnimationController _shakeController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  void _setupAnimations() {
    // Animação de fade in
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut));

    // Animação de pulse para o ícone
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2)
        .animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    
    // Animação de shake para erros
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0.0, end: 10.0)
        .animate(CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn));

    _fadeController.forward();
    _pulseController.repeat(reverse: true);
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      _triggerShakeAnimation();
      return;
    }

    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    final deviceService = Provider.of<DeviceService>(context, listen: false);
    
    // Simula delay de autenticação
    await Future.delayed(const Duration(milliseconds: 1200));

    // Chama o método de login do DeviceService
    final success = await deviceService.login(_passwordController.text);

    if (mounted) {
      if (success) {
        HapticFeedback.lightImpact();
        // Animação de sucesso antes de navegar
        await _showSuccessAnimation();
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        setState(() {
          _errorMessage = 'Credenciais inválidas. Tente novamente.';
          _isLoading = false;
        });
        _triggerShakeAnimation();
        HapticFeedback.vibrate();
      }
    }
  }

  void _triggerShakeAnimation() {
    _shakeController.forward().then((_) {
      _shakeController.reset();
    });
  }

  Future<void> _showSuccessAnimation() async {
    // Pequena animação de sucesso
    await Future.delayed(const Duration(milliseconds: 300));
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _fadeController.dispose();
    _pulseController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.of(context).size;
    
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primary.withOpacity(0.15),
              colorScheme.secondary.withOpacity(0.08),
              colorScheme.surface,
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Efeito de partículas/bubbles decorativas
            ..._buildFloatingElements(colorScheme),
            
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: _buildLoginForm(context, colorScheme, size),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFloatingElements(ColorScheme colorScheme) {
    return List.generate(6, (index) {
      return Positioned(
        top: 50.0 + (index * 120),
        left: (index % 2 == 0) ? -50 : null,
        right: (index % 2 != 0) ? -50 : null,
        child: Container(
          width: 100 + (index * 20),
          height: 100 + (index * 20),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                colorScheme.primary.withOpacity(0.1),
                colorScheme.primary.withOpacity(0.05),
                Colors.transparent,
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildLoginForm(BuildContext context, ColorScheme colorScheme, Size size) {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_shakeAnimation.value, 0),
          child: Card(
            elevation: 20,
            shadowColor: colorScheme.shadow.withOpacity(0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: BorderSide(
                color: colorScheme.outline.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colorScheme.surface,
                    colorScheme.surface.withOpacity(0.95),
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHeader(colorScheme),
                      const SizedBox(height: 48),
                      _buildPasswordField(colorScheme),
                      const SizedBox(height: 32),
                      _buildLoginButton(colorScheme),
                      const SizedBox(height: 24),
                      _buildForgotPassword(colorScheme),
                      const SizedBox(height: 40),
                      _buildFooter(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Column(
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary,
                      colorScheme.secondary,
                      colorScheme.tertiary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withOpacity(0.4),
                      blurRadius: 25,
                      spreadRadius: 2,
                      offset: const Offset(0, 15),
                    ),
                    BoxShadow(
                      color: colorScheme.secondary.withOpacity(0.3),
                      blurRadius: 15,
                      spreadRadius: -5,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.security_rounded,
                  size: 48,
                  color: colorScheme.onPrimary,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 32),
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [colorScheme.primary, colorScheme.secondary],
          ).createShader(bounds),
          child: Text(
            'MDM Sistema',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.primary.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Text(
            'Gerenciamento de Dispositivos Móveis',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: TextFormField(
        controller: _passwordController,
        obscureText: !_isPasswordVisible,
        keyboardType: TextInputType.visiblePassword,
        textInputAction: TextInputAction.done,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Por favor, insira sua senha';
          }
          if (value.length < 4) {
            return 'A senha deve ter pelo menos 4 caracteres';
          }
          return null;
        },
        decoration: InputDecoration(
          labelText: 'Senha',
          hintText: 'Digite sua senha de acesso',
          prefixIcon: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.lock_outline_rounded,
              color: colorScheme.primary,
              size: 20,
            ),
          ),
          suffixIcon: IconButton(
            icon: Icon(
              _isPasswordVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
            onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
          ),
          errorText: _errorMessage,
          errorMaxLines: 2,
          errorStyle: TextStyle(color: colorScheme.error),
          filled: true,
          fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: colorScheme.outline.withOpacity(0.2),
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: colorScheme.primary,
              width: 2,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: colorScheme.error,
              width: 2,
            ),
          ),
        ),
        onFieldSubmitted: (_) => _handleLogin(),
      ),
    );
  }

  Widget _buildLoginButton(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: _isLoading
            ? null
            : LinearGradient(
                colors: [colorScheme.primary, colorScheme.secondary],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
        boxShadow: _isLoading
            ? null
            : [
                BoxShadow(
                  color: colorScheme.primary.withOpacity(0.4),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isLoading ? colorScheme.surfaceVariant : Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: _isLoading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                      strokeWidth: 3,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Autenticando...',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            : Text(
                'Entrar',
                style: TextStyle(
                  color: colorScheme.onPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

  Widget _buildForgotPassword(ColorScheme colorScheme) {
    return TextButton(
      onPressed: () {
        // Implementar funcionalidade de recuperar senha
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Funcionalidade em desenvolvimento'),
            backgroundColor: colorScheme.primary,
          ),
        );
      },
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      child: Text(
        'Esqueceu sua senha?',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Theme.of(context).colorScheme.outline.withOpacity(0.3),
                Colors.transparent,
              ],
            ),
          ),
        ),
        Text(
          'Alexandre Calmon - TI Bahia',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          '© 2025 - Todos os direitos reservados',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                fontSize: 11,
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}