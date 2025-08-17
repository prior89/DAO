#!/bin/bash
echo '🚀 Biometric DAO Installation Script'
echo '==================================='
echo 'npm install && echo "✅ Root dependencies installed"
cd hardwareclient && npm install && echo "✅ Hardware client ready"
cd ../contracts && npm install && echo "✅ Contracts ready"  
cd ../backend && npm install && echo "✅ Backend ready"
cd ../frontend && npm install && echo "✅ Frontend ready"
cd ..
echo "🎉 Installation complete!"'
